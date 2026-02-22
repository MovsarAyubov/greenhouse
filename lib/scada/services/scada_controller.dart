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
  })  : _client = client ?? ModbusTcpClient(),
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

  final List<ZoneState> zones = List<ZoneState>.generate(
    20,
    (i) => ZoneState.initial(i + 1),
  );
  final Map<String, AlarmEntry> _activeAlarms = <String, AlarmEntry>{};
  final List<AlarmEntry> alarmHistory = <AlarmEntry>[];
  final List<TrendPoint> _trendPoints = <TrendPoint>[];
  final Map<int, int> _pendingOutputMaskByZone = <int, int>{};
  final Map<int, int> _pendingApplyTriggerByZone = <int, int>{};

  StreamSubscription<bool>? _connectionSub;
  Timer? _pollTimer;
  DateTime _lastLogAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _applyCounter = 0;

  List<AlarmEntry> get activeAlarms =>
      _activeAlarms.values.toList()..sort((a, b) => b.raisedAt.compareTo(a.raisedAt));

  ZoneState get selectedZone => zones[selectedZoneId - 1];

  Future<void> init() async {
    config = await _configStore.load();
    await _logger.init();
    _connectionSub = _client.connection.listen((value) {
      connected = value;
      notifyListeners();
    });
    await _ensureConnected();
    _startPolling();
    notifyListeners();
  }

  Future<void> saveConfig(ScadaConfig newConfig) async {
    final reconnectNeeded = newConfig.masterIp != config.masterIp ||
        newConfig.masterPort != config.masterPort;
    final pollChanged = newConfig.pollPeriodMs != config.pollPeriodMs;
    config = newConfig;
    await _configStore.save(config);
    if (reconnectNeeded) {
      await _client.disconnect();
      await _ensureConnected();
    }
    if (pollChanged) {
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

  Future<void> _ensureConnected() async {
    if (_client.isConnected || connecting) {
      return;
    }
    connecting = true;
    notifyListeners();
    try {
      await _client.connect(config.masterIp, config.masterPort);
      lastError = null;
    } catch (e) {
      lastError = e.toString();
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(milliseconds: config.pollPeriodMs),
      (_) => unawaited(_pollTick()),
    );
    unawaited(_pollTick());
  }

  Future<void> _pollTick() async {
    if (polling) {
      return;
    }
    polling = true;
    try {
      if (!_client.isConnected) {
        await _ensureConnected();
      }
      if (!_client.isConnected) {
        _markAllZonesOffline();
        return;
      }

      for (var zoneId = 1; zoneId <= zones.length; zoneId++) {
        await _pollZone(zoneId);
      }

      _refreshStaleStates();
      await _logIfNeeded();
      lastError = null;
    } catch (e) {
      lastError = e.toString();
    } finally {
      polling = false;
      notifyListeners();
    }
  }

  Future<void> _pollZone(int zoneId) async {
    final zoneIndex = zoneId - 1;
    final prev = zones[zoneIndex];
    final startedAt = DateTime.now();

    try {
      final regs = await _readZoneWithRetry(zoneId);
      final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
      final next = _decodeZone(prev, regs).copyWith(lastPollMs: elapsed);

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
    } catch (_) {
      zones[zoneIndex] = prev.copyWith(
        online: false,
        stale: true,
        errTimeout: prev.errTimeout + 1,
      );
      _raiseAlarm(
        zoneId: zoneId,
        type: AlarmType.offline,
        message: 'Zone $zoneId is offline',
      );
    }
  }

  ZoneState _decodeZone(ZoneState prev, List<int> regs) {
    int regAt(int idx) => idx < regs.length ? regs[idx] : 0;

    final sensors = List<double>.generate(_registerMap.sensorCount, (i) {
      return _toScaledFromU16(regAt(_registerMap.sensorStart + i));
    });

    final outputMask = regAt(_registerMap.outStateMaskReg);
    final outputs = List<bool>.generate(16, (i) => (outputMask & (1 << i)) != 0);

    final slaveStatus = regAt(_registerMap.slaveStatusReg);
    final online = (slaveStatus & 0x0001) != 0;
    final staleByStatus = (slaveStatus & 0x0002) != 0;
    final ageSec = regAt(_registerMap.lastOkAgeSecReg);
    final staleByAge = ageSec >= config.staleThresholdSec;

    final modeValue = regAt(_registerMap.modeReg);
    final mode = _modeFromReg(modeValue);
    final setpoints = ZoneSetpoints(
      setTemp: _toScaledFromU16(regAt(_registerMap.setTempReg)),
      setHum: _toScaledFromU16(regAt(_registerMap.setHumReg)),
      hystTemp: _toScaledFromU16(regAt(_registerMap.hystTempReg)),
      hystHum: _toScaledFromU16(regAt(_registerMap.hystHumReg)),
      minOnSec: regAt(_registerMap.minOnSecReg),
      minOffSec: regAt(_registerMap.minOffSecReg),
    );

    return prev.copyWith(
      sensors: sensors,
      sensorValidMask: regAt(_registerMap.sensorValidMaskReg),
      outputs: outputs,
      outputCommandMask: regAt(_registerMap.outCmdMaskReg),
      mode: mode,
      setpoints: setpoints,
      online: online,
      stale: staleByStatus || staleByAge,
      lastOkAgeSec: ageSec,
      errTimeout: regAt(_registerMap.errTimeoutReg),
      errCrc: regAt(_registerMap.errCrcReg),
      errException: regAt(_registerMap.errExceptionReg),
      dataVersion: regAt(_registerMap.dataVersionReg),
      lastAppliedTrigger: regAt(_registerMap.lastAppliedTriggerReg),
      lastUpdate: DateTime.now(),
    );
  }

  void _validateZone(ZoneState zone) {
    final hasInvalidMask = (zone.sensorValidMask & 0x01FF) != 0x01FF;
    final hasInvalidRange =
        zone.sensors.any((v) => v.isNaN || v < -100 || v > 200);
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
    final expectedMask = _pendingOutputMaskByZone[zone.zoneId] ??
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

  void _markAllZonesOffline() {
    for (var i = 0; i < zones.length; i++) {
      zones[i] = zones[i].copyWith(online: false, stale: true);
      _raiseAlarm(
        zoneId: zones[i].zoneId,
        type: AlarmType.offline,
        message: 'Zone ${zones[i].zoneId} is offline',
      );
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
      final regs = await _client.readHoldingRegisters(
        unitId: _registerMap.unitId,
        startAddress: base + _registerMap.applyTriggerReg,
        count: 2,
      );
      if (regs.length >= 2 && regs[1] == expected) {
        return true;
      }
    }
    return false;
  }

  Future<List<int>> _readZoneWithRetry(int zoneId) async {
    Object? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _client.readHoldingRegisters(
          unitId: _registerMap.unitId,
          startAddress: _registerMap.zoneReadStart(zoneId),
          count: _registerMap.readCount,
        );
      } catch (e) {
        last = e;
      }
    }
    throw last ?? StateError('Unknown read error');
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

  double _toScaledFromU16(int value) {
    final signed = value >= 0x8000 ? value - 0x10000 : value;
    return signed / 10.0;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _connectionSub?.cancel();
    unawaited(_client.dispose());
    super.dispose();
  }
}
