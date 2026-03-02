import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/scada_models.dart';
import 'config_store.dart';
import 'modbus_tcp_client.dart';
import 'register_map.dart';
import 'scada_logger.dart';

class ScadaController extends ChangeNotifier {
  ScadaController({
    ModbusTcpClient? client,
    ConfigStore? configStore,
    ScadaLogger? logger,
    RegisterMap? registerMap,
  }) : _client = client ?? ModbusTcpClient(),
       _configStore = configStore ?? ConfigStore(),
       _logger = logger ?? ScadaLogger(),
       _registerMap = registerMap ?? RegisterMap.assumed;

  final ModbusTcpClient _client;
  final ConfigStore _configStore;
  final ScadaLogger _logger;
  final RegisterMap _registerMap;

  ScadaConfig config = ScadaConfig.defaults();
  bool connected = false;
  bool connecting = false;
  bool polling = false;
  String? lastError;
  int selectedZoneId = 1;
  int? serverRtcHour;
  int? serverRtcMinute;
  DateTime? serverRtcLastUpdate;
  String? serverRtcLastError;

  final List<ZoneState> zones = List<ZoneState>.generate(
    1,
    (i) => ZoneState.initial(i + 1),
  );
  WeatherStationState weather = WeatherStationState.initial();
  final Map<String, AlarmEntry> _activeAlarms = <String, AlarmEntry>{};
  final List<AlarmEntry> alarmHistory = <AlarmEntry>[];
  final List<TrendPoint> _trendPoints = <TrendPoint>[];
  final Map<int, int> _pendingOutputMaskByZone = <int, int>{};
  final Map<int, int> _pendingApplyTriggerByZone = <int, int>{};
  final List<String> _clientTrace = <String>[];
  static const int _clientTraceLimit = 1200;

  StreamSubscription<bool>? _connectionSub;
  Timer? _pollTimer;
  DateTime _lastLogAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _applyCounter = 0;
  final List<int> _readRetryBackoffMs = <int>[250];
  final int _degradedAfterConsecutiveTimeouts = 2;
  final Duration _degradedReconnectCooldown = const Duration(seconds: 20);
  final int _offlineAfterConsecutiveFailedPolls = 3;
  final Duration _staleAfterNoSuccess = const Duration(milliseconds: 12000);
  final Duration _offlineAfterNoSuccess = const Duration(milliseconds: 30000);
  int? _resolvedDirectoryBase;
  int _resolvedMapFlags = 0;
  int _resolvedPointCount = 0;
  int _resolvedPointStride = 0;
  int _resolvedPointsBase = 0;
  int? _zoneModuleId;
  int _zoneExpectedSensorCount = 0;
  final Map<String, int> _preferredReadStartByOperation = <String, int>{};
  int _consecutiveReadTimeouts = 0;
  bool _degraded = false;
  DateTime _lastDegradedReconnectAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _consecutiveFailedPolls = 0;
  DateTime _lastSuccessfulPollAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _connectivityPolicyState = 0; // 0=normal,1=stale,2=offline
  int _pollSeq = 0;
  int _rtcSetTokenCounter = 0;

  List<AlarmEntry> get activeAlarms =>
      _activeAlarms.values.toList()
        ..sort((a, b) => b.raisedAt.compareTo(a.raisedAt));

  ZoneState get selectedZone => zones[selectedZoneId - 1];
  List<String> get clientTrace => List<String>.unmodifiable(_clientTrace);
  String get serverRtcText {
    final hour = serverRtcHour;
    final minute = serverRtcMinute;
    if (hour == null || minute == null) {
      return '--:--';
    }
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  Future<void> init() async {
    final loaded = await _configStore.load();
    final normalized = loaded.copyWith(
      pollPeriodMs: _normalizePollPeriodMs(loaded.pollPeriodMs),
    );
    config = normalized;
    if (normalized.pollPeriodMs != loaded.pollPeriodMs) {
      await _configStore.save(normalized);
    }
    await _logger.init();
    _lastSuccessfulPollAt = DateTime.now();
    _addClientTrace(
      'controller init poll_ms=${config.pollPeriodMs} '
      'ip=${config.masterIp} port=${config.masterPort} '
      'profile(timeout_ms=1800,retries_total=${_readRetryBackoffMs.length + 1},'
      'backoff=${_readRetryBackoffMs.join("/")},degraded_after=$_degradedAfterConsecutiveTimeouts,'
      'degraded_reconnect_ms=${_degradedReconnectCooldown.inMilliseconds},'
      'offline_after_failed=$_offlineAfterConsecutiveFailedPolls,'
      'stale_after_no_success_ms=${_staleAfterNoSuccess.inMilliseconds},'
      'offline_after_no_success_ms=${_offlineAfterNoSuccess.inMilliseconds})',
    );
    _connectionSub = _client.connection.listen((value) {
      connected = value;
      _addClientTrace(value ? 'connected' : 'disconnected');
      notifyListeners();
    });
    await _ensureConnected();
    _startPolling();
    notifyListeners();
  }

  Future<void> saveConfig(ScadaConfig newConfig) async {
    final normalizedConfig = newConfig.copyWith(
      pollPeriodMs: _normalizePollPeriodMs(newConfig.pollPeriodMs),
    );
    final reconnectNeeded =
        normalizedConfig.masterIp != config.masterIp ||
        normalizedConfig.masterPort != config.masterPort;
    final pollChanged = normalizedConfig.pollPeriodMs != config.pollPeriodMs;
    config = normalizedConfig;
    await _configStore.save(config);
    if (reconnectNeeded) {
      _addClientTrace('settings changed: reconnect requested');
      await _client.disconnect();
      _invalidateDirectoryCache();
      await _ensureConnected();
    }
    if (pollChanged) {
      _addClientTrace(
        'settings changed: poll period updated to ${config.pollPeriodMs}ms',
      );
      _startPolling();
    }
    notifyListeners();
  }

  void selectZone(int zoneId) {
    if (zoneId < 1 || zoneId > zones.length) {
      return;
    }
    selectedZoneId = zoneId;
    notifyListeners();
  }

  Future<void> applyCommand({
    required int zoneId,
    required ZoneCommandDraft draft,
  }) async {
    final index = zoneId - 1;
    if (index < 0 || index >= zones.length) {
      return;
    }
    if (!zones[index].online) {
      throw StateError('Zone is offline. Write is forbidden.');
    }

    final base = _registerMap.zoneBase(zoneId);
    final write20to26 = <int>[
      _modeToReg(draft.mode),
      _toU16FromScaledSigned(draft.setpoints.setTemp),
      _toU16FromScaledSigned(draft.setpoints.setHum),
      _toU16FromScaledSigned(draft.setpoints.hystTemp),
      _toU16FromScaledSigned(draft.setpoints.hystHum),
      draft.setpoints.minOnSec & 0xFFFF,
      draft.setpoints.minOffSec & 0xFFFF,
    ];

    await _client.writeMultipleRegisters(
      unitId: _registerMap.unitId,
      startAddress: base + _registerMap.modeReg,
      values: write20to26,
    );

    if (draft.mode == ZoneMode.manual) {
      final outputMask = _boolListToMask16(draft.outputsManual);
      _pendingOutputMaskByZone[zoneId] = outputMask;
      await _client.writeSingleRegister(
        unitId: _registerMap.unitId,
        address: base + _registerMap.outCmdMaskReg,
        value: outputMask,
      );
    }

    _applyCounter = (_applyCounter + 1) & 0xFFFF;
    _pendingApplyTriggerByZone[zoneId] = _applyCounter;
    await _client.writeSingleRegister(
      unitId: _registerMap.unitId,
      address: base + _registerMap.applyTriggerReg,
      value: _applyCounter,
    );

    final ok = await _waitApplyAck(zoneId, _applyCounter);
    if (!ok) {
      throw StateError(
        'Apply not confirmed: LAST_APPLIED_TRIGGER did not reach $_applyCounter',
      );
    }
    _pendingApplyTriggerByZone.remove(zoneId);
  }

  Future<void> setServerRtcTime({
    required int hour,
    required int minute,
  }) async {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw RangeError(
        'RTC_SET out of range: hour=$hour minute=$minute (expected 0..23 / 0..59)',
      );
    }

    serverRtcLastError = null;
    final token = await _nextRtcSetToken();
    _addClientTrace('rtc_set start hour=$hour minute=$minute token=$token');
    notifyListeners();

    try {
      await _writeSingleWithRetry(
        address: _registerMap.rtcSetHourAddress,
        value: hour,
        operationName: 'rtc_set_hour',
      );
      await _writeSingleWithRetry(
        address: _registerMap.rtcSetMinuteAddress,
        value: minute,
        operationName: 'rtc_set_minute',
      );
      await _writeSingleWithRetry(
        address: _registerMap.rtcSetTokenAddress,
        value: token,
        operationName: 'rtc_set_token',
      );

      final deadline = DateTime.now().add(const Duration(seconds: 8));
      var lastAppliedToken = -1;
      var lastResult = -1;
      while (DateTime.now().isBefore(deadline)) {
        final regs = await _readHoldingWithRetry(
          startAddress: _registerMap.rtcSetAppliedTokenAddress,
          count: 2,
          operationName: 'rtc_set_state',
          maxAttempts: 1,
        );
        if (regs.length < 2) {
          throw StateError('RTC_SET state read too short: ${regs.length}/2');
        }

        lastAppliedToken = regs[0] & 0xFFFF;
        lastResult = regs[1] & 0xFFFF;

        if (lastResult == 3) {
          throw StateError('RTC_SET rejected: REJECT_RANGE');
        }
        if (lastResult == 4) {
          throw StateError('RTC_SET failed: FAILED');
        }
        if (lastAppliedToken == token && (lastResult == 2 || lastResult == 0)) {
          await _pollServerRtc();
          _addClientTrace(
            'rtc_set applied token=$token result=${_rtcSetResultLabel(lastResult)}',
          );
          notifyListeners();
          return;
        }

        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      throw TimeoutException(
        'RTC_SET not confirmed: token=$token '
        'applied=$lastAppliedToken result=${_rtcSetResultLabel(lastResult)}',
      );
    } catch (e) {
      serverRtcLastError = e.toString();
      _addClientTrace('rtc_set error token=$token: $e');
      notifyListeners();
      rethrow;
    }
  }

  List<TrendPoint> trendPoints({
    required int zoneId,
    required Set<int> sensors,
    required Duration window,
  }) {
    final cutoff = DateTime.now().subtract(window);
    return _trendPoints.where((p) {
      return p.zoneId == zoneId &&
          sensors.contains(p.sensorIndex) &&
          p.time.isAfter(cutoff);
    }).toList();
  }

  void ackAlarm(String alarmId) {
    AlarmEntry? entry;
    for (final item in _activeAlarms.values) {
      if (item.id == alarmId) {
        entry = item;
        break;
      }
    }
    if (entry == null || entry.acknowledged) {
      return;
    }
    final key = _alarmKey(entry.zoneId, entry.type);
    final updated = entry.copyWith(acknowledged: true);
    _activeAlarms[key] = updated;
    _replaceHistory(updated);
    unawaited(_logger.logAlarm(updated, event: 'ack'));
    notifyListeners();
  }

  Future<void> exportCsv() async {
    // Data is continuously appended in logs/telemetry.csv and logs/alarms.csv.
  }

  void clearClientTrace() {
    _clientTrace.clear();
    _addClientTrace('trace cleared');
    notifyListeners();
  }

  Future<void> _ensureConnected() async {
    if (_client.isConnected || connecting) {
      return;
    }
    connecting = true;
    _addClientTrace(
      'connect attempt host=${config.masterIp} port=${config.masterPort}',
    );
    notifyListeners();
    try {
      await _client.connect(config.masterIp, config.masterPort);
      lastError = null;
      _addClientTrace('connect ok');
    } catch (e) {
      lastError = e.toString();
      _addClientTrace('connect error: $e');
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _addClientTrace('poll timer set period_ms=${config.pollPeriodMs}');
    _pollTimer = Timer.periodic(
      Duration(milliseconds: config.pollPeriodMs),
      (_) => unawaited(_pollTick()),
    );
    unawaited(_pollTick());
  }

  Future<void> _pollTick() async {
    if (polling) {
      _addClientTrace('poll skipped: previous cycle in progress');
      return;
    }
    final pollId = ++_pollSeq;
    final startedAt = DateTime.now();
    _addClientTrace('poll start #$pollId');
    polling = true;
    try {
      if (!_client.isConnected) {
        await _ensureConnected();
      }
      if (!_client.isConnected) {
        _addClientTrace('poll #$pollId: still disconnected');
        _consecutiveFailedPolls += 1;
        _applyNoSuccessPolicy();
        lastError = 'not connected';
        return;
      }

      await _ensureDirectoryReady();
      await _pollServerRtc();
      final rows = await _readPointsRowsWithRetry();
      final groupedRows = _groupRowsByModule(rows);

      for (var zoneId = 1; zoneId <= zones.length; zoneId++) {
        await _pollZone(zoneId, groupedRows);
      }
      await _pollWeather(rows);

      _refreshStaleStates();
      _consecutiveFailedPolls = 0;
      _lastSuccessfulPollAt = DateTime.now();
      _applyNoSuccessPolicy();
      await _logIfNeeded();
      lastError = null;
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      _addClientTrace(
        'poll ok #$pollId duration_ms=$elapsedMs '
        'degraded=${_degraded ? 1 : 0} timeout_streak=$_consecutiveReadTimeouts',
      );
    } catch (e) {
      lastError = e.toString();
      weather = weather.copyWith(lastError: e.toString());
      for (var i = 0; i < zones.length; i++) {
        final prev = zones[i];
        zones[i] = prev.copyWith(errTimeout: prev.errTimeout + 1);
      }
      _consecutiveFailedPolls += 1;
      _applyNoSuccessPolicy();
      _addClientTrace('poll error #$pollId: $e');
    } finally {
      polling = false;
      notifyListeners();
    }
  }

  Future<void> _pollZone(
    int zoneId,
    Map<int, List<_PointRow>> groupedRows,
  ) async {
    final zoneIndex = zoneId - 1;
    final prev = zones[zoneIndex];
    final startedAt = DateTime.now();

    try {
      final zoneRows = _resolveZoneRows(groupedRows);
      final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
      final next = _decodeZoneFromPoints(
        prev,
        zoneRows,
      ).copyWith(lastPollMs: elapsed);

      zones[zoneIndex] = next;
      if (next.online) {
        _clearAlarm(zoneId, AlarmType.offline);
      } else {
        _raiseAlarm(
          zoneId: zoneId,
          type: AlarmType.offline,
          message: 'Zone $zoneId is offline',
        );
      }
      _validateZone(next);
      _checkCommandMatch(next);
      _checkApplyTrigger(zoneId, next);
    } catch (e) {
      zones[zoneIndex] = prev.copyWith(
        online: false,
        stale: true,
        errTimeout: prev.errTimeout + 1,
      );
      lastError = e.toString();
      _raiseAlarm(
        zoneId: zoneId,
        type: AlarmType.offline,
        message: 'Zone $zoneId is offline',
      );
    }
  }

  ZoneState _decodeZoneFromPoints(ZoneState prev, List<_PointRow> rows) {
    final sensors = List<double>.filled(_registerMap.sensorCount, 0);
    final sensorQualityCodes = List<int>.filled(_registerMap.sensorCount, 3);
    final sensorAgeSec = List<int>.filled(_registerMap.sensorCount, 0);
    final sensorFlags = List<int>.filled(_registerMap.sensorCount, 0);
    var sensorValidMask = 0;
    var maxAgeSec = 0;

    for (var i = 0; i < _registerMap.sensorCount; i++) {
      if (i >= rows.length) {
        sensors[i] = prev.sensors[i];
        continue;
      }
      final row = rows[i];
      final value = _toFloat32FromHiLo(row.valueHi, row.valueLo);
      final quality = row.quality & 0xFFFF;
      final ageSec = row.ageSec & 0xFFFF;
      final flags = row.flags & 0xFFFF;
      final flagValid = (flags & _registerMap.pointValidFlagMask) != 0;
      final usableValue = flagValid && quality == 0 && value.isFinite;

      sensorQualityCodes[i] = quality;
      sensorAgeSec[i] = ageSec;
      sensorFlags[i] = flags;
      sensors[i] = usableValue ? value : prev.sensors[i];
      if (usableValue) {
        sensorValidMask |= (1 << i);
      }
      if (ageSec > maxAgeSec) {
        maxAgeSec = ageSec;
      }
    }

    final mapValid = (_resolvedMapFlags & 0x0001) != 0;
    final topologyActive = (_resolvedMapFlags & 0x0002) != 0;
    final online = mapValid && topologyActive && rows.isNotEmpty;
    final hasQualityWarning = sensorQualityCodes.any((q) => q != 0);
    final staleByAge = maxAgeSec >= config.staleThresholdSec;

    return prev.copyWith(
      sensors: sensors,
      sensorValidMask: sensorValidMask,
      sensorQualityCodes: sensorQualityCodes,
      sensorAgeSec: sensorAgeSec,
      sensorFlags: sensorFlags,
      online: online,
      stale: hasQualityWarning || staleByAge || !topologyActive,
      lastOkAgeSec: maxAgeSec,
      dataVersion: _resolvedPointCount,
      lastUpdate: DateTime.now(),
    );
  }

  WeatherStationState _decodeWeatherFromPoints(List<_PointRow> rows) {
    final count = _registerMap.weatherPointCount;
    final values = List<double?>.filled(count, null);
    final qualityCodes = List<int>.filled(count, 3);
    final ageSec = List<int>.filled(count, 0);
    final flags = List<int>.filled(count, 0);

    for (var i = 0; i < count; i++) {
      if (i >= rows.length) {
        continue;
      }
      final row = rows[i];
      final value = _toFloat32FromHiLo(row.valueHi, row.valueLo);
      qualityCodes[i] = row.quality & 0xFFFF;
      ageSec[i] = row.ageSec & 0xFFFF;
      flags[i] = row.flags & 0xFFFF;
      values[i] = value.isFinite ? value : null;
    }

    final hasAnyLivePoint = List<bool>.generate(
      count,
      (i) =>
          ((flags[i] & _registerMap.pointValidFlagMask) != 0) &&
          qualityCodes[i] != 3 &&
          values[i] != null,
    ).any((v) => v);
    final online = rows.length >= count && hasAnyLivePoint;

    return weather.copyWith(
      values: values,
      qualityCodes: qualityCodes,
      ageSec: ageSec,
      flags: flags,
      online: online,
    );
  }

  Future<void> _pollWeather(List<_PointRow> allRows) async {
    try {
      final weatherRows = _resolveWeatherRowsFromPoints(allRows);
      weather = _decodeWeatherFromPoints(
        weatherRows,
      ).copyWith(lastUpdate: DateTime.now(), clearLastError: true);
    } catch (e) {
      weather = weather.copyWith(online: false, lastError: e.toString());
    }
  }

  Future<void> _pollServerRtc() async {
    try {
      final regs = await _readHoldingAtCandidates(
        startCandidates: <int>[_registerMap.rtcHourAddress],
        count: 2,
        operationName: 'rtc_hhmm',
      );
      if (regs.length < 2) {
        throw StateError('RTC read too short: ${regs.length}/2');
      }
      final hour = regs[0] & 0xFFFF;
      final minute = regs[1] & 0xFFFF;
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        throw StateError('RTC out of range: hour=$hour minute=$minute');
      }
      serverRtcHour = hour;
      serverRtcMinute = minute;
      serverRtcLastUpdate = DateTime.now();
      serverRtcLastError = null;
    } catch (e) {
      serverRtcLastError = e.toString();
    }
  }

  List<_PointRow> _resolveWeatherRowsFromPoints(List<_PointRow> allRows) {
    final start = _registerMap.weatherPublishStartIndex;
    final count = _registerMap.weatherPointCount;
    final end = start + count;
    if (allRows.length < end) {
      throw StateError(
        'Weather rows are incomplete: have=${allRows.length}, '
        'need_at_least=$end',
      );
    }
    final rows = allRows.sublist(start, end);
    for (final row in rows) {
      if (row.moduleId != _registerMap.weatherExpectedModuleId) {
        throw StateError(
          'Unexpected weather module_id=${row.moduleId}, '
          'expected=${_registerMap.weatherExpectedModuleId}',
        );
      }
    }
    return rows;
  }

  Map<int, List<_PointRow>> _groupRowsByModule(List<_PointRow> rows) {
    final grouped = <int, List<_PointRow>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.moduleId, () => <_PointRow>[]).add(row);
    }
    return grouped;
  }

  List<_PointRow> _resolveZoneRows(Map<int, List<_PointRow>> groupedRows) {
    List<_PointRow> takeRows(List<_PointRow> source) {
      final rows = source.take(_registerMap.sensorCount).toList();
      _zoneExpectedSensorCount = rows.length;
      return rows;
    }

    bool isZoneModule(int moduleId) {
      return moduleId != _registerMap.weatherExpectedModuleId;
    }

    if (_zoneModuleId != null && isZoneModule(_zoneModuleId!)) {
      final cached = groupedRows[_zoneModuleId!];
      if (cached != null && cached.isNotEmpty) {
        return takeRows(cached);
      }
    }

    final orderedModuleIds = groupedRows.keys.toList()..sort();

    for (final moduleId in orderedModuleIds) {
      if (!isZoneModule(moduleId)) {
        continue;
      }
      final rows = groupedRows[moduleId];
      if (rows == null || rows.isEmpty) {
        continue;
      }
      _zoneModuleId = moduleId;
      return takeRows(rows);
    }

    for (final moduleId in orderedModuleIds) {
      final rows = groupedRows[moduleId];
      if (rows == null || rows.isEmpty) {
        continue;
      }
      _zoneModuleId = moduleId;
      return takeRows(rows);
    }

    _zoneExpectedSensorCount = 0;
    return const <_PointRow>[];
  }

  Future<void> _ensureDirectoryReady() async {
    if (_resolvedDirectoryBase != null) {
      return;
    }

    Object? lastError;
    for (final base in _registerMap.directoryBaseCandidates) {
      try {
        final regs = await _readHoldingWithRetry(
          startAddress: base,
          count: _registerMap.directoryReadCount,
          operationName: 'directory@$base',
          maxAttempts: 1,
        );
        if (regs.length < _registerMap.directoryReadCount) {
          throw StateError(
            'Directory read too short: ${regs.length}/${_registerMap.directoryReadCount}',
          );
        }

        final mapVersion = regs[_registerMap.mapVersionReg];
        final pointStride = regs[_registerMap.pointStrideReg];
        final mapFlags = regs[_registerMap.mapFlagsReg];
        final pointCount = regs[_registerMap.pointCountReg] & 0xFFFF;
        final pointsBase = regs[_registerMap.pointsBaseReg];
        if (mapVersion != _registerMap.expectedMapVersion ||
            pointStride != _registerMap.expectedPointStride) {
          throw StateError(
            'Incompatible map contract: MAP_VERSION=$mapVersion '
            '(expected ${_registerMap.expectedMapVersion}), '
            'POINT_STRIDE=$pointStride (expected ${_registerMap.expectedPointStride})',
          );
        }
        if ((mapFlags & 0x0001) == 0) {
          throw StateError(
            'Directory map is invalid: MAP_FLAGS=0x${mapFlags.toRadixString(16)}',
          );
        }
        if (pointCount != _registerMap.expectedPointCount) {
          throw StateError(
            'Unexpected Directory POINT_COUNT=$pointCount '
            '(expected ${_registerMap.expectedPointCount})',
          );
        }

        _resolvedDirectoryBase = base;
        _resolvedMapFlags = mapFlags;
        _resolvedPointCount = pointCount;
        _resolvedPointStride = pointStride;
        _resolvedPointsBase = pointsBase;
        return;
      } catch (e) {
        lastError = e;
      }
    }

    _invalidateDirectoryCache();
    throw lastError ?? StateError('Failed to resolve Directory');
  }

  Future<List<_PointRow>> _readPointsRowsWithRetry() async {
    await _ensureDirectoryReady();

    final rowCount = _resolvedPointCount > _registerMap.expectedPointCount
        ? _registerMap.expectedPointCount
        : _resolvedPointCount;
    if (rowCount <= 0) {
      throw StateError('POINT_COUNT is 0');
    }

    final totalRegs = rowCount * _resolvedPointStride;
    final regs = <int>[];
    var regOffset = 0;
    while (regOffset < totalRegs) {
      final remainingRegs = totalRegs - regOffset;
      final maxRowsPerReq = 20; // 20 * 6 = 120, below FC03 limit 125
      final remainingRows = remainingRegs ~/ _resolvedPointStride;
      final rowsInChunk = remainingRows > maxRowsPerReq
          ? maxRowsPerReq
          : remainingRows;
      final chunkRegs = rowsInChunk * _resolvedPointStride;
      final startAddress = _resolvedPointsBase + regOffset;
      final chunk = await _readHoldingAtCandidates(
        startCandidates: _addressCandidates(startAddress),
        count: chunkRegs,
        operationName: 'points',
      );
      regs.addAll(chunk);
      regOffset += chunkRegs;
    }

    final rows = <_PointRow>[];
    for (var i = 0; i < rowCount; i++) {
      final base = i * _resolvedPointStride;
      rows.add(
        _PointRow(
          valueHi: regs[base + _registerMap.pointValueHiReg],
          valueLo: regs[base + _registerMap.pointValueLoReg],
          quality: regs[base + _registerMap.pointQualityReg],
          ageSec: regs[base + _registerMap.pointAgeSecReg],
          moduleId: regs[base + _registerMap.pointModuleIdReg],
          flags: regs[base + _registerMap.pointFlagsReg],
        ),
      );
    }
    return rows;
  }

  void _validateZone(ZoneState zone) {
    final expectedCount = _zoneExpectedSensorCount > 0
        ? _zoneExpectedSensorCount
        : _registerMap.sensorCount;
    final expectedMask = expectedCount >= 16
        ? 0xFFFF
        : ((1 << expectedCount) - 1);
    final hasInvalidMask =
        (zone.sensorValidMask & expectedMask) != expectedMask;
    final hasInvalidRange = zone.sensors.any(
      (v) => v.isNaN || v < -100 || v > 200,
    );
    final hasInvalid = hasInvalidMask || hasInvalidRange;
    if (hasInvalid) {
      _raiseAlarm(
        zoneId: zone.zoneId,
        type: AlarmType.invalidSensor,
        message: 'Zone ${zone.zoneId}: invalid sensor value',
      );
    } else {
      _clearAlarm(zone.zoneId, AlarmType.invalidSensor);
    }
  }

  void _checkCommandMatch(ZoneState zone) {
    final expectedMask =
        _pendingOutputMaskByZone[zone.zoneId] ??
        (zone.mode == ZoneMode.manual ? zone.outputCommandMask : null);
    if (expectedMask == null || zone.mode != ZoneMode.manual) {
      _clearAlarm(zone.zoneId, AlarmType.commandMismatch);
      return;
    }
    final actualMask = _boolListToMask16(zone.outputs);
    if (actualMask != expectedMask) {
      _raiseAlarm(
        zoneId: zone.zoneId,
        type: AlarmType.commandMismatch,
        message:
            'Zone ${zone.zoneId}: command/state mismatch (expected $expectedMask, actual $actualMask)',
      );
      return;
    }
    _pendingOutputMaskByZone.remove(zone.zoneId);
    _clearAlarm(zone.zoneId, AlarmType.commandMismatch);
  }

  void _refreshStaleStates() {
    for (var i = 0; i < zones.length; i++) {
      final zone = zones[i];
      final stale = zone.stale || zone.lastOkAgeSec >= config.staleThresholdSec;
      if (zone.stale != stale) {
        zones[i] = zone.copyWith(stale: stale);
      }
      if (stale) {
        _raiseAlarm(
          zoneId: zone.zoneId,
          type: AlarmType.stale,
          message: 'Zone ${zone.zoneId}: stale data',
        );
      } else {
        _clearAlarm(zone.zoneId, AlarmType.stale);
      }
    }
  }

  Future<void> _logIfNeeded() async {
    final now = DateTime.now();
    if (now.difference(_lastLogAt).inSeconds < config.logPeriodSec) {
      return;
    }
    _lastLogAt = now;
    for (final zone in zones) {
      await _logger.logZone(zone);
      for (var i = 0; i < zone.sensors.length; i++) {
        _trendPoints.add(
          TrendPoint(
            time: now,
            zoneId: zone.zoneId,
            sensorIndex: i,
            value: zone.sensors[i],
          ),
        );
      }
    }
    if (_trendPoints.length > 12000) {
      _trendPoints.removeRange(0, 6000);
    }
  }

  void _applyNoSuccessPolicy() {
    final lastSuccess = _lastSuccessfulPollAt;
    if (lastSuccess.millisecondsSinceEpoch <= 0) {
      return;
    }
    final elapsed = DateTime.now().difference(lastSuccess);
    final forceOffline =
        _consecutiveFailedPolls >= _offlineAfterConsecutiveFailedPolls ||
        elapsed >= _offlineAfterNoSuccess;
    final forceStale = !forceOffline && elapsed >= _staleAfterNoSuccess;

    final nextState = forceOffline ? 2 : (forceStale ? 1 : 0);
    if (nextState != _connectivityPolicyState) {
      _connectivityPolicyState = nextState;
      _addClientTrace(
        'connectivity policy state=$nextState elapsed_ms=${elapsed.inMilliseconds} '
        'failed_polls=$_consecutiveFailedPolls',
      );
    }

    if (forceOffline) {
      weather = weather.copyWith(online: false);
      for (var i = 0; i < zones.length; i++) {
        zones[i] = zones[i].copyWith(online: false, stale: true);
        _raiseAlarm(
          zoneId: zones[i].zoneId,
          type: AlarmType.offline,
          message: 'Zone ${zones[i].zoneId} is offline',
        );
      }
      return;
    }

    if (forceStale) {
      for (var i = 0; i < zones.length; i++) {
        zones[i] = zones[i].copyWith(stale: true);
      }
    }
  }

  void _raiseAlarm({
    required int zoneId,
    required AlarmType type,
    required String message,
  }) {
    final key = _alarmKey(zoneId, type);
    if (_activeAlarms.containsKey(key)) {
      return;
    }
    final entry = AlarmEntry(
      id: '${zoneId}_${type.name}_${DateTime.now().millisecondsSinceEpoch}',
      zoneId: zoneId,
      type: type,
      message: message,
      raisedAt: DateTime.now(),
      acknowledged: false,
    );
    _activeAlarms[key] = entry;
    alarmHistory.insert(0, entry);
    unawaited(_logger.logAlarm(entry, event: 'raise'));
  }

  void _clearAlarm(int zoneId, AlarmType type) {
    final key = _alarmKey(zoneId, type);
    final active = _activeAlarms[key];
    if (active == null) {
      return;
    }
    final cleared = active.copyWith(clearedAt: DateTime.now());
    _activeAlarms.remove(key);
    _replaceHistory(cleared);
    unawaited(_logger.logAlarm(cleared, event: 'clear'));
  }

  void _replaceHistory(AlarmEntry entry) {
    final idx = alarmHistory.indexWhere((a) => a.id == entry.id);
    if (idx >= 0) {
      alarmHistory[idx] = entry;
    }
  }

  String _alarmKey(int zoneId, AlarmType type) => '$zoneId:${type.name}';

  ZoneMode _modeFromReg(int value) {
    switch (value) {
      case 1:
        return ZoneMode.manual;
      case 2:
        return ZoneMode.service;
      case 0:
      default:
        return ZoneMode.auto;
    }
  }

  int _modeToReg(ZoneMode mode) {
    switch (mode) {
      case ZoneMode.auto:
        return 0;
      case ZoneMode.manual:
        return 1;
      case ZoneMode.service:
        return 2;
    }
  }

  int _boolListToMask16(List<bool> values) {
    var out = 0;
    final max = values.length < 16 ? values.length : 16;
    for (var i = 0; i < max; i++) {
      if (values[i]) {
        out |= (1 << i);
      }
    }
    return out;
  }

  Future<bool> _waitApplyAck(int zoneId, int expected) async {
    final base = _registerMap.zoneBase(zoneId);
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final regs = await _readHoldingWithRetry(
        startAddress: base + _registerMap.applyTriggerReg,
        count: 2,
        operationName: 'apply_ack',
      );
      if (regs.length >= 2 && regs[1] == expected) {
        return true;
      }
    }
    return false;
  }

  Future<void> _writeSingleWithRetry({
    required int address,
    required int value,
    required String operationName,
    int? maxAttempts,
  }) async {
    Object? last;
    final attemptLimit = maxAttempts ?? (_readRetryBackoffMs.length + 1);
    for (var attempt = 0; attempt < attemptLimit; attempt++) {
      try {
        if (!_client.isConnected) {
          await _ensureConnected();
        }
        if (!_client.isConnected) {
          throw StateError('not connected');
        }
        _addClientTrace(
          'send write op=$operationName addr=$address value=$value '
          'attempt=${attempt + 1}/$attemptLimit',
        );
        await _client.writeSingleRegister(
          unitId: _registerMap.unitId,
          address: address,
          value: value & 0xFFFF,
        );
        _addClientTrace(
          'write ok op=$operationName attempt=${attempt + 1}/$attemptLimit',
        );
        return;
      } catch (e) {
        last = e;
        _addClientTrace(
          'write error op=$operationName attempt=${attempt + 1}/$attemptLimit: $e',
        );
        if (_isModbusException(e)) {
          rethrow;
        }
        final mustForceDisconnect = _shouldForceDisconnectAfterReadError(e);
        if (mustForceDisconnect && _client.isConnected) {
          _addClientTrace('disconnect after write error op=$operationName: $e');
          await _client.disconnect();
        }
        if (attempt < _readRetryBackoffMs.length &&
            attempt < (attemptLimit - 1)) {
          await Future<void>.delayed(
            Duration(milliseconds: _readRetryBackoffMs[attempt]),
          );
          continue;
        }
      }
    }
    if (last != null) {
      throw StateError('Write failed: $operationName: $last');
    }
    throw StateError('Write failed: $operationName');
  }

  Future<int> _nextRtcSetToken() async {
    var next = (_rtcSetTokenCounter + 1) & 0xFFFF;
    if (next == 0) {
      next = 1;
    }

    try {
      final regs = await _readHoldingWithRetry(
        startAddress: _registerMap.rtcSetAppliedTokenAddress,
        count: 1,
        operationName: 'rtc_set_applied_token_precheck',
        maxAttempts: 1,
      );
      if (regs.isNotEmpty) {
        final applied = regs[0] & 0xFFFF;
        if (next == applied) {
          next = (next + 1) & 0xFFFF;
          if (next == 0) {
            next = 1;
          }
        }
      }
    } catch (_) {
      // Best effort: token generation should not fail the write path.
    }

    _rtcSetTokenCounter = next;
    return next;
  }

  Future<List<int>> _readHoldingWithRetry({
    required int startAddress,
    required int count,
    required String operationName,
    int? maxAttempts,
  }) async {
    Object? last;
    final attemptLimit = maxAttempts ?? (_readRetryBackoffMs.length + 1);
    for (var attempt = 0; attempt < attemptLimit; attempt++) {
      try {
        if (!_client.isConnected) {
          await _ensureConnected();
        }
        if (!_client.isConnected) {
          throw StateError('not connected');
        }
        final requestStartedAt = DateTime.now();
        _addClientTrace(
          'send op=$operationName start=$startAddress count=$count '
          'attempt=${attempt + 1}/$attemptLimit',
        );
        final regs = await _client.readHoldingRegisters(
          unitId: _registerMap.unitId,
          startAddress: startAddress,
          count: count,
        );
        _consecutiveReadTimeouts = 0;
        _degraded = false;
        final elapsedMs = DateTime.now()
            .difference(requestStartedAt)
            .inMilliseconds;
        _addClientTrace(
          'recv ok op=$operationName regs=${regs.length} '
          'attempt=${attempt + 1} duration_ms=$elapsedMs',
        );
        return regs;
      } catch (e) {
        last = e;
        final timeoutError = _isReadTimeout(e);
        if (timeoutError) {
          _consecutiveReadTimeouts += 1;
          if (_consecutiveReadTimeouts >= _degradedAfterConsecutiveTimeouts) {
            _degraded = true;
          }
          _addClientTrace(
            'timeout op=$operationName start=$startAddress count=$count '
            'attempt=${attempt + 1}/$attemptLimit '
            'streak=$_consecutiveReadTimeouts degraded=${_degraded ? 1 : 0}',
          );
        }
        if (_isModbusException(e)) {
          _addClientTrace('modbus exception op=$operationName: $e');
          rethrow;
        }
        final mustForceDisconnect = _shouldForceDisconnectAfterReadError(e);
        if (mustForceDisconnect && _client.isConnected) {
          _addClientTrace('disconnect after error op=$operationName: $e');
          await _client.disconnect();
        }
        if (timeoutError && _degraded && _shouldReconnectInDegradedMode()) {
          _lastDegradedReconnectAt = DateTime.now();
          _addClientTrace('degraded reconnect start op=$operationName');
          if (_client.isConnected) {
            await _client.disconnect();
          }
          await _ensureConnected();
          _addClientTrace('degraded reconnect done op=$operationName');
        }
        if (attempt < _readRetryBackoffMs.length &&
            attempt < (attemptLimit - 1)) {
          _addClientTrace(
            'retry scheduled op=$operationName next_in_ms=${_readRetryBackoffMs[attempt]} '
            'after_error=$e',
          );
          await Future<void>.delayed(
            Duration(milliseconds: _readRetryBackoffMs[attempt]),
          );
          continue;
        }
      }
    }
    if (last != null) {
      final degradedTag = _degraded
          ? ' [degraded, timeout_streak=$_consecutiveReadTimeouts]'
          : '';
      _addClientTrace('read failed op=$operationName error=$last$degradedTag');
      throw StateError('Read failed: $operationName: $last$degradedTag');
    }
    throw StateError('Read failed: $operationName');
  }

  void _checkApplyTrigger(int zoneId, ZoneState zone) {
    final pending = _pendingApplyTriggerByZone[zoneId];
    if (pending == null) {
      return;
    }
    if (zone.lastAppliedTrigger == pending) {
      _pendingApplyTriggerByZone.remove(zoneId);
    }
  }

  int _toU16FromScaledSigned(double value) {
    final scaled = (value * 10).round();
    return scaled & 0xFFFF;
  }

  bool _shouldForceDisconnectAfterReadError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('not connected') ||
        message.contains('disconnected') ||
        message.contains('connection reset') ||
        message.contains('broken pipe') ||
        message.contains('software caused connection abort') ||
        message.contains('connection aborted') ||
        message.contains('connection refused') ||
        message.contains('socketexception') ||
        message.contains('socket write failed') ||
        message.contains('forcibly closed') ||
        message.contains('wsaec');
  }

  bool _isModbusException(Object error) {
    return error.toString().toLowerCase().contains('modbus exception code:');
  }

  String _rtcSetResultLabel(int code) {
    switch (code) {
      case 0:
        return 'IDLE';
      case 1:
        return 'QUEUED';
      case 2:
        return 'APPLIED';
      case 3:
        return 'REJECT_RANGE';
      case 4:
        return 'FAILED';
      default:
        return 'UNKNOWN($code)';
    }
  }

  bool _isIllegalDataAddress(Object error) {
    return error.toString().toLowerCase().contains('modbus exception code: 2');
  }

  bool _isRetryableTransportError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('response timeout') ||
        message.contains('timeout') ||
        message.contains('not connected') ||
        message.contains('disconnected') ||
        message.contains('connection reset') ||
        message.contains('broken pipe') ||
        message.contains('software caused connection abort') ||
        message.contains('connection aborted') ||
        message.contains('connection refused') ||
        message.contains('socketexception') ||
        message.contains('socket write failed') ||
        message.contains('forcibly closed') ||
        message.contains('wsaec');
  }

  bool _isReadTimeout(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('response timeout') || message.contains('timeout');
  }

  bool _shouldReconnectInDegradedMode() {
    final now = DateTime.now();
    return now.difference(_lastDegradedReconnectAt) >=
        _degradedReconnectCooldown;
  }

  void _addClientTrace(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '$timestamp $message';
    _clientTrace.insert(0, line);
    if (_clientTrace.length > _clientTraceLimit) {
      _clientTrace.removeRange(_clientTraceLimit, _clientTrace.length);
    }
    unawaited(_logger.logClientEvent(message));
  }

  List<int> _addressCandidates(int startAddress) {
    return <int>[startAddress];
  }

  Future<List<int>> _readHoldingAtCandidates({
    required List<int> startCandidates,
    required int count,
    required String operationName,
  }) async {
    final dedupedCandidates = <int>[];
    for (final candidate in startCandidates) {
      if (candidate < 0 || dedupedCandidates.contains(candidate)) {
        continue;
      }
      dedupedCandidates.add(candidate);
    }
    final preferredCandidate = _preferredReadStartByOperation[operationName];
    if (preferredCandidate != null &&
        dedupedCandidates.contains(preferredCandidate)) {
      dedupedCandidates
        ..remove(preferredCandidate)
        ..insert(0, preferredCandidate);
    }
    if (dedupedCandidates.length > 1) {
      _addClientTrace(
        'candidates op=$operationName values=${dedupedCandidates.join('/')}, '
        'preferred=${preferredCandidate ?? '-'}',
      );
    }

    Object? last;
    for (final candidate in dedupedCandidates) {
      final hasAlternatives = dedupedCandidates.length > 1;
      final candidateAttempts = hasAlternatives
          ? 1
          : (_readRetryBackoffMs.length + 1);
      try {
        final regs = await _readHoldingWithRetry(
          startAddress: candidate,
          count: count,
          operationName: '$operationName@$candidate',
          maxAttempts: candidateAttempts,
        );
        _preferredReadStartByOperation[operationName] = candidate;
        _addClientTrace(
          'candidate selected op=$operationName start=$candidate',
        );
        return regs;
      } catch (e) {
        last = e;
        _addClientTrace(
          'candidate failed op=$operationName start=$candidate: $e',
        );
        if (_isIllegalDataAddress(e) || _isRetryableTransportError(e)) {
          continue;
        }
        rethrow;
      }
    }
    throw last ??
        StateError('Read failed for all address candidates: $operationName');
  }

  void _invalidateDirectoryCache() {
    _resolvedDirectoryBase = null;
    _resolvedMapFlags = 0;
    _resolvedPointCount = 0;
    _resolvedPointStride = 0;
    _resolvedPointsBase = 0;
    _zoneModuleId = null;
    _zoneExpectedSensorCount = 0;
    _preferredReadStartByOperation.clear();
    _consecutiveReadTimeouts = 0;
    _degraded = false;
    _lastDegradedReconnectAt = DateTime.fromMillisecondsSinceEpoch(0);
    _consecutiveFailedPolls = 0;
    _connectivityPolicyState = 0;
  }

  int _normalizePollPeriodMs(int value) {
    return 5000;
  }

  double _toFloat32FromHiLo(int hi, int lo) {
    final raw = ((hi & 0xFFFF) << 16) | (lo & 0xFFFF);
    final data = ByteData(4)..setUint32(0, raw, Endian.big);
    return data.getFloat32(0, Endian.big);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _connectionSub?.cancel();
    unawaited(_client.dispose());
    super.dispose();
  }
}

class _PointRow {
  const _PointRow({
    required this.valueHi,
    required this.valueLo,
    required this.quality,
    required this.ageSec,
    required this.moduleId,
    required this.flags,
  });

  final int valueHi;
  final int valueLo;
  final int quality;
  final int ageSec;
  final int moduleId;
  final int flags;
}
