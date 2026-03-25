import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import '../models/lighting_schedule_models.dart';
import '../models/scada_models.dart';
import '../models/topology_models.dart';
import 'command_builder.dart';
import 'config_store.dart';
import 'modbus_tcp_client.dart';
import 'register_map.dart';
import 'register_map_runtime.dart';
import 'scada_logger.dart';
import 'topology_resolver.dart';
import 'topology_store.dart';
import 'topology_uploader.dart';

class ScadaController extends ChangeNotifier {
  ScadaController({
    ModbusTcpClient? client,
    ConfigStore? configStore,
    ScadaLogger? logger,
    RegisterMap? registerMap,
    TopologyStore? topologyStore,
  }) : _client = client ?? ModbusTcpClient(),
       _configStore = configStore ?? ConfigStore(),
       _logger = logger ?? ScadaLogger(),
       _registerMap = registerMap ?? RegisterMap.assumed,
       _topologyStore = topologyStore ?? TopologyStore(),
       _commandBuilder = const CommandBuilder() {
    _client.traceSink = _addClientTrace;
  }

  final ModbusTcpClient _client;
  final ConfigStore _configStore;
  final ScadaLogger _logger;
  final RegisterMap _registerMap;
  final TopologyStore _topologyStore;
  final CommandBuilder _commandBuilder;

  late final RegisterMapRuntime _registerMapRuntime = RegisterMapRuntime(
    client: _client,
    registerMap: _registerMap,
  );
  late final TopologyUploader _topologyUploader = TopologyUploader(
    client: _client,
    registerMap: _registerMap,
  );

  ScadaConfig config = ScadaConfig.defaults();
  bool connected = false;
  bool connecting = false;
  bool polling = false;
  bool topologyUploading = false;
  bool scheduleSending = false;
  String? lastError;
  String? uploadStatus;
  String? serverRtcLastError;
  DateTime? serverRtcLastUpdate;
  int? serverRtcHour;
  int? serverRtcMinute;
  DiagnosticsSnapshot? diagnosticsSnapshot;
  DateTime? diagnosticsLastUpdate;
  String? diagnosticsLastError;

  CompatibilityStatus compatibility = const CompatibilityStatus(
    state: ScadaCompatibilityState.localTopologyMissing,
    message: 'Local topology manifest is not loaded.',
  );

  RegisterDirectorySnapshot? directorySnapshot;
  DeviceTopologyMetadata? deviceTopologyMetadata;
  TopologyStoreSnapshot topologySnapshot = TopologyStoreSnapshot.empty;
  TopologyResolver? topologyResolver;

  final Map<int, PointTelemetryValue> _telemetryByPublishIndex =
      <int, PointTelemetryValue>{};
  final Map<int, SlaveStatusSnapshot> _slaveStatusBySlaveId =
      <int, SlaveStatusSnapshot>{};
  final Map<int, LightingScheduleDraft> _persistedLightingDraftByModuleId =
      <int, LightingScheduleDraft>{};
  final Map<int, LightingScheduleStatus> _scheduleStatusByModuleId =
      <int, LightingScheduleStatus>{};
  final List<String> _clientTrace = <String>[];

  StreamSubscription<bool>? _connectionSub;
  Timer? _pollTimer;
  int _lightingTriggerCounter = 0;
  int _topologySubmitToken = 100;
  int _pollingPauseDepth = 0;
  DateTime? _lastDiagnosticsPollAt;
  DateTime? _lastSessionRefreshAttemptAt;
  bool _disposed = false;

  // Use the full Modbus FC3 window now that the server handles large reads
  // without the earlier timeout/stall behavior.
  static const int _maxPointRegsPerRead = 125;
  static const int _maxSlaveStatusRegsPerRead = 125;
  static const Duration _sessionRefreshInterval = Duration(seconds: 30);
  static const int _minScheduleApplyWaitMs = 2000;
  static const int _maxScheduleApplyWaitMs = 3000;
  static const int _minSchedulePollIntervalMs = 100;
  static const int _maxSchedulePollIntervalMs = 200;
  static const int _scheduleResultIdle = 0;
  static const int _scheduleResultQueued = 1;
  static const int _scheduleResultApplied = 2;

  List<String> get clientTrace => List<String>.unmodifiable(_clientTrace);
  List<TopologyModule> get zoneModules =>
      topologyResolver?.zoneModules ?? const <TopologyModule>[];
  List<TopologyModule> get weatherModules =>
      topologyResolver?.weatherModules ?? const <TopologyModule>[];

  SlaveStatusSnapshot? slaveStatusForModule(int moduleId) {
    final module = topologyResolver?.moduleById(moduleId);
    if (module == null || module.slaveId <= 0) {
      return null;
    }
    return _slaveStatusBySlaveId[module.slaveId];
  }

  String get serverRtcText {
    final hour = serverRtcHour;
    final minute = serverRtcMinute;
    if (hour == null || minute == null) {
      return '--:--';
    }
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  bool get canReadTelemetry {
    if (compatibility.state == ScadaCompatibilityState.ready) {
      return true;
    }
    return compatibility.state ==
            ScadaCompatibilityState.topologyGenerationMismatch &&
        config.featureFlags.allowTelemetryOnGenerationMismatch;
  }

  bool get canReadRuntimeTelemetryFallback {
    if (compatibility.state != ScadaCompatibilityState.localTopologyMissing) {
      return false;
    }
    final directory = directorySnapshot;
    final device = deviceTopologyMetadata;
    return directory != null &&
        device != null &&
        directory.topologyActive &&
        device.isActive;
  }

  bool get canUseRtc =>
      compatibility.state == ScadaCompatibilityState.ready ||
      compatibility.state == ScadaCompatibilityState.topologyGenerationMismatch;

  bool get pollingPaused => _pollingPauseDepth > 0;

  bool get canUploadTopology =>
      compatibility.state != ScadaCompatibilityState.mapIncompatible &&
      topologySnapshot.blob != null &&
      topologySnapshot.manifest != null;

  bool get canSendCommands =>
      compatibility.state == ScadaCompatibilityState.ready && !scheduleSending;

  List<ModuleSummary> get moduleSummaries => _buildModuleSummaries();
  List<RuntimeModuleTelemetryView> get runtimeTelemetryModules =>
      _buildRuntimeTelemetryModules();

  Future<void> init() async {
    config = await _configStore.load();
    _persistedLightingDraftByModuleId
      ..clear()
      ..addAll(await _configStore.loadLightingDrafts());
    await _logger.init();
    _applyClientConfig();
    _connectionSub = _client.connection.listen((value) {
      connected = value;
      if (!value) {
        _lastSessionRefreshAttemptAt = null;
      }
      _addClientTrace(value ? 'connected' : 'disconnected');
      notifyListeners();
    });
    await _loadLocalTopology();
    await _ensureConnected();
    await refreshSession();
    _startPolling();
  }

  Future<void> saveConfig(ScadaConfig newConfig) async {
    config = newConfig;
    await _configStore.save(config);
    _applyClientConfig();
    await _loadLocalTopology();
    if (_client.isConnected) {
      await refreshSession();
    }
    _startPolling();
    notifyListeners();
  }

  Future<void> reloadLocalTopology() async {
    await _loadLocalTopology();
  }

  Future<void> refreshSession({
    bool reloadLocalTopology = true,
    bool abortOnTransportError = false,
  }) async {
    if (_disposed) {
      return;
    }
    if (reloadLocalTopology) {
      await _loadLocalTopology(
        notifyAfterLoad: false,
        recomputeAfterLoad: false,
      );
    }
    if (!_client.isConnected) {
      if (!_disposed) {
        notifyListeners();
      }
      return;
    }
    _lastSessionRefreshAttemptAt = DateTime.now();
    final bootstrap = await _registerMapRuntime.bootstrap();
    if (bootstrap.directory != null) {
      directorySnapshot = bootstrap.directory;
    }
    if (bootstrap.topologyMetadata != null) {
      deviceTopologyMetadata = bootstrap.topologyMetadata;
    }
    if (directorySnapshot != null) {
      serverRtcHour = directorySnapshot!.rtcHour;
      serverRtcMinute = directorySnapshot!.rtcMinute;
      serverRtcLastUpdate = DateTime.now();
      serverRtcLastError = null;
    }
    if (bootstrap.bootstrapError != null) {
      lastError = bootstrap.bootstrapError;
      _addClientTrace('bootstrap read error: ${bootstrap.bootstrapError}');
      _recomputeCompatibility();
      if (abortOnTransportError &&
          _isRetryableTransportError(bootstrap.bootstrapError!)) {
        throw _PollingTransportAbort(bootstrap.bootstrapError!);
      }
      if (!_disposed) {
        notifyListeners();
      }
      return;
    }
    if (bootstrap.contractError != null) {
      compatibility = CompatibilityStatus(
        state: ScadaCompatibilityState.mapIncompatible,
        message: bootstrap.contractError!,
      );
    } else {
      _recomputeCompatibility();
    }
    _topologySubmitToken = maxU16(
      _topologySubmitToken,
      deviceTopologyMetadata?.resultToken ?? 0,
    );
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _loadLocalTopology({
    bool notifyAfterLoad = true,
    bool recomputeAfterLoad = true,
  }) async {
    topologySnapshot = await _topologyStore.load(
      manifestPath: config.localTopologyManifestPath,
      blobPath: config.localTopologyBlobPath,
      semanticCatalogPath: config.semanticCatalogPath,
    );
    topologyResolver = topologySnapshot.manifest == null
        ? null
        : TopologyResolver(topologySnapshot.manifest!);
    _rebuildScheduleStates();
    if (recomputeAfterLoad) {
      _recomputeCompatibility();
    }
    if (notifyAfterLoad) {
      notifyListeners();
    }
  }

  List<ResolvedPointValue> resolvedPointsForModule(int moduleId) {
    final resolver = topologyResolver;
    if (resolver == null) {
      return const <ResolvedPointValue>[];
    }
    return resolver
        .pointsForModule(moduleId)
        .map((point) {
          final telemetry = _telemetryByPublishIndex[point.publishIndex];
          final message = telemetry == null
              ? 'No runtime row for publish_index=${point.publishIndex}'
              : _qualityLabel(telemetry.quality);
          return ResolvedPointValue(
            point: point,
            telemetry: telemetry,
            pointContractState: ScadaCompatibilityState.ready,
            statusMessage: message,
          );
        })
        .toList(growable: false);
  }

  List<SemanticFieldView> weatherFieldsForModule(int moduleId) {
    return _weatherSemantics
        .map((semantic) {
          final point = topologyResolver?.pointBySemantic(
            moduleId: moduleId,
            semanticName: semantic.semanticName,
          );
          if (point == null) {
            return SemanticFieldView(
              semanticName: semantic.semanticName,
              label: semantic.label,
              unit: semantic.unit,
              decimals: semantic.decimals,
              point: null,
              telemetry: null,
              state: ScadaCompatibilityState.pointContractMissing,
              message: 'Point contract missing',
            );
          }
          return SemanticFieldView(
            semanticName: semantic.semanticName,
            label: semantic.label,
            unit: semantic.unit,
            decimals: semantic.decimals,
            point: point,
            telemetry: _telemetryByPublishIndex[point.publishIndex],
            state: ScadaCompatibilityState.ready,
            message: 'publish_index=${point.publishIndex}',
          );
        })
        .toList(growable: false);
  }

  List<SemanticFieldView> lightingFeedbackFieldsForModule(int moduleId) {
    return _lightingFeedbackSemantics
        .map((semantic) {
          final point = topologyResolver?.pointBySemantic(
            moduleId: moduleId,
            semanticName: semantic.semanticName,
          );
          if (point == null) {
            return SemanticFieldView(
              semanticName: semantic.semanticName,
              label: semantic.label,
              unit: semantic.unit,
              decimals: semantic.decimals,
              point: null,
              telemetry: null,
              state: ScadaCompatibilityState.pointContractMissing,
              message: 'Point contract missing',
            );
          }
          return SemanticFieldView(
            semanticName: semantic.semanticName,
            label: semantic.label,
            unit: semantic.unit,
            decimals: semantic.decimals,
            point: point,
            telemetry: _telemetryByPublishIndex[point.publishIndex],
            state: ScadaCompatibilityState.ready,
            message: 'publish_index=${point.publishIndex}',
          );
        })
        .toList(growable: false);
  }

  LightingScheduleStatus lightingStatusForModule(int moduleId) {
    final existing = _scheduleStatusByModuleId[moduleId];
    if (existing != null) {
      return existing;
    }
    final module = topologyResolver?.moduleById(moduleId);
    if (module == null) {
      throw StateError('Unknown module_id=$moduleId');
    }
    final created = LightingScheduleStatus.initial(
      moduleId: module.moduleId,
      zoneId: module.zoneId,
      slaveId: module.slaveId,
    ).copyWith(
      draft: _draftForModule(module: module),
    );
    _scheduleStatusByModuleId[moduleId] = created;
    return created;
  }

  String? scheduleDisabledReasonForModule(int moduleId) {
    if (compatibility.state != ScadaCompatibilityState.ready) {
      return compatibility.message;
    }
    final resolver = topologyResolver;
    if (resolver == null) {
      return 'Local topology manifest is not loaded.';
    }
    final module = resolver.moduleById(moduleId);
    if (module == null) {
      return 'Selected module is missing in topology.';
    }
    if (resolver.scheduleContractForModule(moduleId) == null) {
      return 'Lighting setpoints profile is absent for this module.';
    }
    return null;
  }

  void updateLightingDraft(
    int moduleId,
    LightingScheduleDraft Function(LightingScheduleDraft current) update,
  ) {
    final current = lightingStatusForModule(moduleId);
    _scheduleStatusByModuleId[moduleId] = current.copyWith(
      draft: update(current.draft),
    );
    notifyListeners();
  }

  Future<void> sendScheduleForModule(int moduleId) async {
    final disabledReason = scheduleDisabledReasonForModule(moduleId);
    if (disabledReason != null) {
      final current = lightingStatusForModule(moduleId);
      _scheduleStatusByModuleId[moduleId] = current.copyWith(
        phase: LightingSchedulePhase.failed,
        message: disabledReason,
      );
      notifyListeners();
      return;
    }

    final resolver = topologyResolver!;
    final module = resolver.moduleById(moduleId)!;
    final contract = resolver.scheduleContractForModule(moduleId)!;
    final current = lightingStatusForModule(moduleId);
    final request = _commandBuilder.buildScheduleCommand(
      module: module,
      contract: contract,
      draft: current.draft,
    );
    scheduleSending = true;
    _scheduleStatusByModuleId[moduleId] = current.copyWith(
      phase: LightingSchedulePhase.pending,
      lastAttemptAt: DateTime.now(),
      clearMessage: true,
    );
    notifyListeners();

    try {
      final status = await _runWithPollingPause('schedule_apply', () async {
        await _ensureMapCompatible();
        final preState = await _readHoldingWithRetry(
          startAddress: directorySnapshot!.cmdBase,
          count: _registerMap.expectedCmdBlockSize,
          operationName: 'schedule_pre_state',
        );
        final lastApplied =
            preState[_registerMap.cmdLastAppliedTriggerOffset] & 0xFFFF;
        final trigger = _nextLightingTrigger(lastAppliedTrigger: lastApplied);
        final payloadRegs = <int>[
          request.targetSlaveId & 0xFFFF,
          request.targetModuleId & 0xFFFF,
          request.cmdProfileId & 0xFFFF,
          request.payload.length & 0xFFFF,
          ...request.payload,
        ];
        final payloadLastOffset = payloadRegs.length - 1;
        await _logger.logScheduleTransaction(
          moduleId: module.moduleId,
          slaveId: module.slaveId,
          event: 'payload_write_req',
          operation: 'FC16_CMD+0..+$payloadLastOffset',
          address: directorySnapshot!.cmdBase,
          count: payloadRegs.length,
          requestRegs: payloadRegs,
          trigger: trigger,
          lastAppliedTrigger: lastApplied,
        );
        await _writeMultipleWithRetry(
          startAddress: directorySnapshot!.cmdBase,
          values: payloadRegs,
          operationName: 'schedule_payload',
        );
        await _writeSingleWithRetry(
          address: directorySnapshot!.cmdBase + _registerMap.cmdTriggerOffset,
          value: trigger,
          operationName: 'schedule_trigger',
        );
        await _persistLastSentLightingDraft(
          module: module,
          draft: current.draft,
        );

        return _pollForScheduleResult(
          module: module,
          trigger: trigger,
          timeoutMs: request.timeoutMs > 0
              ? request.timeoutMs
              : config.timeouts.commandMs,
        );
      });
      _scheduleStatusByModuleId[moduleId] = status;
    } catch (e) {
      _scheduleStatusByModuleId[moduleId] = current.copyWith(
        phase: LightingSchedulePhase.failed,
        lastAttemptAt: DateTime.now(),
        message: e.toString(),
      );
    } finally {
      scheduleSending = false;
      notifyListeners();
    }
  }

  Future<void> setServerRtcTime({
    required int hour,
    required int minute,
  }) async {
    if (!canUseRtc) {
      throw StateError(compatibility.message);
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw RangeError('RTC_SET out of range');
    }
    await _runWithPollingPause('rtc_set', () async {
      await _ensureMapCompatible();
      final token = await _nextRtcSetToken();
      await _writeMultipleWithRetry(
        startAddress:
            _registerMap.directoryBase + _registerMap.rtcSetHourOffset,
        values: <int>[hour, minute, token],
        operationName: 'rtc_set_triplet',
      );

      final deadline = DateTime.now().add(
        Duration(milliseconds: config.timeouts.commandMs),
      );
      while (DateTime.now().isBefore(deadline)) {
        final regs = await _readHoldingWithRetry(
          startAddress:
              _registerMap.directoryBase +
              _registerMap.rtcSetAppliedTokenOffset,
          count: 2,
          operationName: 'rtc_set_state',
        );
        final lastAppliedToken = regs[0] & 0xFFFF;
        final result = regs[1] & 0xFFFF;
        if (lastAppliedToken == token) {
          if (result == 2) {
            await refreshSession();
            return;
          }
          throw StateError('RTC_SET failed: $result');
        }
        await Future<void>.delayed(
          Duration(milliseconds: config.pollIntervals.commandPollMs),
        );
      }
      throw TimeoutException('RTC_SET not confirmed');
    });
  }

  Future<void> uploadTopology() async {
    if (!canUploadTopology) {
      throw StateError('Topology upload is not available in current state.');
    }
    topologyUploading = true;
    uploadStatus = 'Uploading topology...';
    notifyListeners();
    try {
      final summary = await _runWithPollingPause('topology_upload', () async {
        await _ensureMapCompatible();
        final manifest = topologySnapshot.manifest!;
        final blob = topologySnapshot.blob!;
        return _topologyUploader.upload(
          blob: blob,
          generation: manifest.generation,
          startToken: _topologySubmitToken + 1,
          pollInterval: Duration(
            milliseconds: config.pollIntervals.uploadPollMs,
          ),
          chunkTimeout: Duration(milliseconds: config.timeouts.uploadChunkMs),
          commitTimeout: Duration(milliseconds: config.timeouts.uploadCommitMs),
        );
      });
      _topologySubmitToken += summary.chunksUploaded;
      _telemetryByPublishIndex.clear();
      _slaveStatusBySlaveId.clear();
      await refreshSession();
      uploadStatus =
          'Upload complete. generation=${summary.activeGeneration} '
          'size=${summary.activeSizeBytes}';
    } catch (e) {
      uploadStatus = 'Upload failed: $e';
      rethrow;
    } finally {
      topologyUploading = false;
      notifyListeners();
    }
  }

  Future<void> reconnect() async {
    await _client.disconnect();
    await _ensureConnected();
    await refreshSession();
  }

  Future<void> _ensureConnected() async {
    if (_client.isConnected || connecting) {
      return;
    }
    connecting = true;
    notifyListeners();
    try {
      await _client.connect(
        config.deviceConnection.host,
        config.deviceConnection.port,
      );
      connected = true;
      lastError = null;
    } catch (e) {
      lastError = e.toString();
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  void _applyClientConfig() {
    _client.addressMode = config.addressMode;
    _client.connectTimeout = Duration(milliseconds: config.timeouts.connectMs);
    _client.responseTimeout = Duration(
      milliseconds: config.timeouts.responseMs,
    );
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(milliseconds: config.pollIntervals.telemetryMs),
      (_) => unawaited(_pollTick()),
    );
    unawaited(_pollTick());
  }

  Future<void> _pollTick() async {
    if (_disposed ||
        polling ||
        topologyUploading ||
        scheduleSending ||
        pollingPaused) {
      return;
    }
    polling = true;
    try {
      if (!_client.isConnected) {
        await _ensureConnected();
      }
      if (!_client.isConnected) {
        return;
      }
      await _refreshSessionIfDue(
        force: directorySnapshot == null || deviceTopologyMetadata == null,
      );
      await _pollDiagnosticsIfDue();
      if (canReadTelemetry || canReadRuntimeTelemetryFallback) {
        await _pollTelemetry();
      } else {
        _telemetryByPublishIndex.clear();
        _slaveStatusBySlaveId.clear();
      }
      lastError = null;
    } on _PollingTransportAbort catch (e) {
      lastError = e.message;
      _addClientTrace('poll cycle aborted: ${e.message}');
    } catch (e) {
      lastError = e.toString();
      _addClientTrace('poll error: $e');
    } finally {
      polling = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> _refreshSessionIfDue({bool force = false}) async {
    final lastAttemptAt = _lastSessionRefreshAttemptAt;
    if (!force &&
        lastAttemptAt != null &&
        DateTime.now().difference(lastAttemptAt) < _sessionRefreshInterval) {
      return;
    }
    await refreshSession(
      reloadLocalTopology: false,
      abortOnTransportError: true,
    );
  }

  Future<void> _pollDiagnosticsIfDue() async {
    final lastPollAt = _lastDiagnosticsPollAt;
    final intervalMs = config.pollIntervals.diagMs;
    if (lastPollAt != null &&
        DateTime.now().difference(lastPollAt).inMilliseconds < intervalMs) {
      return;
    }
    _lastDiagnosticsPollAt = DateTime.now();
    try {
      final regs = await _readHoldingWithRetry(
        startAddress: _registerMap.diagBase,
        count: 32,
        operationName: 'diag_window',
      );
      diagnosticsSnapshot = DiagnosticsSnapshot(
        bootCount: _joinU32(regs[0], regs[1]),
        powerOnCount: _joinU32(regs[2], regs[3]),
        errorHandlerCount: _joinU32(regs[4], regs[5]),
        watchdogMissCount: _joinU32(regs[6], regs[7]),
        faultResetCount: _joinU32(regs[8], regs[9]),
        lastEventCode: _joinU32(regs[10], regs[11]),
        lastResetReason: _joinU32(regs[12], regs[13]),
        lastErrorCode: _joinU32(regs[14], regs[15]),
        modbusTimeout0: _joinU32(regs[16], regs[17]),
        modbusTimeout1: _joinU32(regs[18], regs[19]),
        tcpAcceptErrCount: _joinU32(regs[20], regs[21]),
        tcpRecvTimeoutCount: _joinU32(regs[22], regs[23]),
        tcpStaleCloseCount: _joinU32(regs[24], regs[25]),
        tcpMalformedMbapCount: _joinU32(regs[26], regs[27]),
        tcpSendErrCount: _joinU32(regs[28], regs[29]),
        tcpLastErr: _toSignedI32(regs[30], regs[31]),
      );
      diagnosticsLastUpdate = DateTime.now();
      diagnosticsLastError = null;
    } catch (e) {
      diagnosticsLastError = e.toString();
      if (_isRetryableTransportError(e)) {
        throw _PollingTransportAbort(e.toString());
      }
    }
  }

  Future<void> _pollTelemetry() async {
    final directory = directorySnapshot;
    if (directory == null) {
      return;
    }
    final telemetry = await _readPointsRows(directory);
    _telemetryByPublishIndex
      ..clear()
      ..addAll(telemetry);
    final statuses = await _readSlaveStatuses();
    _slaveStatusBySlaveId
      ..clear()
      ..addAll(statuses);
  }

  Future<Map<int, PointTelemetryValue>> _readPointsRows(
    RegisterDirectorySnapshot directory,
  ) async {
    final out = <int, PointTelemetryValue>{};
    final maxRowsPerChunk = directory.pointStride <= 0
        ? 1
        : ((_maxPointRegsPerRead ~/ directory.pointStride) < 1
              ? 1
              : (_maxPointRegsPerRead ~/ directory.pointStride));
    var row = 0;
    while (row < directory.pointCount) {
      final remainingRows = directory.pointCount - row;
      final rowsInChunk = remainingRows > maxRowsPerChunk
          ? maxRowsPerChunk
          : remainingRows;
      final regs = await _readHoldingWithRetry(
        startAddress: directory.pointsBase + row * directory.pointStride,
        count: rowsInChunk * directory.pointStride,
        operationName: 'points_chunk_$row',
      );
      for (var index = 0; index < rowsInChunk; index++) {
        final base = index * directory.pointStride;
        out[row + index] = PointTelemetryValue(
          value: _toFloat32FromHiLo(
            regs[base + _registerMap.pointValueHiReg],
            regs[base + _registerMap.pointValueLoReg],
          ),
          quality: regs[base + _registerMap.pointQualityReg] & 0xFFFF,
          ageSec: regs[base + _registerMap.pointAgeSecReg] & 0xFFFF,
          moduleId: regs[base + _registerMap.pointModuleIdReg] & 0xFFFF,
          flags: regs[base + _registerMap.pointFlagsReg] & 0xFFFF,
        );
      }
      row += rowsInChunk;
    }
    return out;
  }

  Future<Map<int, SlaveStatusSnapshot>> _readSlaveStatuses() async {
    final resolver = topologyResolver;
    if (resolver == null || resolver.manifest.modules.isEmpty) {
      return const <int, SlaveStatusSnapshot>{};
    }
    final slaveIds = resolver.manifest.modules
        .map((module) => module.slaveId)
        .where((slaveId) => slaveId > 0)
        .toSet()
        .toList(growable: false)
      ..sort();
    if (slaveIds.isEmpty) {
      return const <int, SlaveStatusSnapshot>{};
    }
    final out = <int, SlaveStatusSnapshot>{};
    final regsPerStatus = _registerMap.expectedStatusBlockSize;
    final maxStatusesPerChunk = regsPerStatus <= 0
        ? 1
        : ((_maxSlaveStatusRegsPerRead ~/ regsPerStatus) < 1
              ? 1
              : (_maxSlaveStatusRegsPerRead ~/ regsPerStatus));
    var runStart = slaveIds.first;
    var runEnd = runStart;
    for (var index = 1; index <= slaveIds.length; index++) {
      final currentSlaveId = index < slaveIds.length ? slaveIds[index] : -1;
      if (currentSlaveId == runEnd + 1) {
        runEnd = currentSlaveId;
        continue;
      }

      await _readSlaveStatusRange(
        firstSlaveId: runStart,
        lastSlaveId: runEnd,
        regsPerStatus: regsPerStatus,
        maxStatusesPerChunk: maxStatusesPerChunk,
        out: out,
      );

      if (index < slaveIds.length) {
        runStart = currentSlaveId;
        runEnd = currentSlaveId;
      }
    }
    return out;
  }

  Future<void> _readSlaveStatusRange({
    required int firstSlaveId,
    required int lastSlaveId,
    required int regsPerStatus,
    required int maxStatusesPerChunk,
    required Map<int, SlaveStatusSnapshot> out,
  }) async {
    var slaveId = firstSlaveId;
    while (slaveId <= lastSlaveId) {
      final remaining = lastSlaveId - slaveId + 1;
      final statusesInChunk = remaining > maxStatusesPerChunk
          ? maxStatusesPerChunk
          : remaining;
      final regs = await _readHoldingWithRetry(
        startAddress:
            _registerMap.slaveStatusBase + (slaveId - 1) * regsPerStatus,
        count: statusesInChunk * regsPerStatus,
        operationName: 'slave_status_${slaveId - 1}',
      );
      for (var index = 0; index < statusesInChunk; index++) {
        final base = index * regsPerStatus;
        final currentSlaveId = slaveId + index;
        out[currentSlaveId] = SlaveStatusSnapshot(
          statusFlags:
              regs[base + _registerMap.slaveStatusStatusOffset] & 0xFFFF,
          lastOkAgeSec:
              regs[base + _registerMap.slaveStatusLastOkAgeOffset] & 0xFFFF,
          errTimeout:
              regs[base + _registerMap.slaveStatusErrTimeoutOffset] & 0xFFFF,
          errCrc: regs[base + _registerMap.slaveStatusErrCrcOffset] & 0xFFFF,
          errException:
              regs[base + _registerMap.slaveStatusErrExceptionOffset] & 0xFFFF,
          dataVersion:
              regs[base + _registerMap.slaveStatusDataVersionOffset] & 0xFFFF,
          validMask:
              regs[base + _registerMap.slaveStatusValidMaskOffset] & 0xFFFF,
          outStateMask:
              regs[base + _registerMap.slaveStatusOutStateMaskOffset] & 0xFFFF,
        );
      }
      slaveId += statusesInChunk;
    }
  }

  Future<LightingScheduleStatus> _pollForScheduleResult({
    required TopologyModule module,
    required int trigger,
    required int timeoutMs,
  }) async {
    final effectiveTimeoutMs = timeoutMs < _minScheduleApplyWaitMs
        ? _minScheduleApplyWaitMs
        : (timeoutMs > _maxScheduleApplyWaitMs
              ? _maxScheduleApplyWaitMs
              : timeoutMs);
    final pollIntervalMs = _effectiveSchedulePollIntervalMs;
    final deadline = DateTime.now().add(Duration(milliseconds: effectiveTimeoutMs));
    var lastApplied = 0;
    var lastResult = 0;
    var lastIoErr = 0;
    LightingScheduleStatus? deferredFailure;
    while (DateTime.now().isBefore(deadline)) {
      final regs = await _readHoldingWithRetry(
        startAddress:
            directorySnapshot!.cmdBase +
            _registerMap.cmdLastAppliedTriggerOffset,
        count: 3,
        operationName: 'schedule_poll',
      );
      lastApplied = regs[0] & 0xFFFF;
      lastResult = regs[1] & 0xFFFF;
      lastIoErr = regs[2] & 0xFFFF;
      await _logger.logScheduleTransaction(
        moduleId: module.moduleId,
        slaveId: module.slaveId,
        event: 'poll_read',
        operation: 'FC3_CMD+21..+23',
        address:
            directorySnapshot!.cmdBase +
            _registerMap.cmdLastAppliedTriggerOffset,
        count: 3,
        responseRegs: regs,
        trigger: trigger,
        lastAppliedTrigger: lastApplied,
        lastResult: lastResult,
        lastIoErr: lastIoErr,
      );
      if (lastApplied == trigger && lastResult == _scheduleResultApplied) {
        return lightingStatusForModule(module.moduleId).copyWith(
          phase: LightingSchedulePhase.success,
          trigger: trigger,
          lastAppliedTrigger: lastApplied,
          lastResult: lastResult,
          lastIoErr: lastIoErr,
          lastAttemptAt: DateTime.now(),
          message: 'Applied',
        );
      }
      if (lastApplied == trigger && lastResult == _scheduleResultQueued) {
        deferredFailure = null;
      } else if (lastApplied == trigger &&
          lastResult != _scheduleResultIdle &&
          lastResult != _scheduleResultApplied) {
        deferredFailure = lightingStatusForModule(module.moduleId).copyWith(
          phase: LightingSchedulePhase.failed,
          trigger: trigger,
          lastAppliedTrigger: lastApplied,
          lastResult: lastResult,
          lastIoErr: lastIoErr,
          lastAttemptAt: DateTime.now(),
          message:
              'Rejected: ${lightingResultLabel(lastResult)} '
              '(io=${lightingIoErrLabel(lastIoErr)})',
        );
      }
      await Future<void>.delayed(
        Duration(milliseconds: pollIntervalMs),
      );
    }
    if (deferredFailure != null) {
      return deferredFailure;
    }
    return lightingStatusForModule(module.moduleId).copyWith(
      phase: LightingSchedulePhase.timeout,
      trigger: trigger,
      lastAppliedTrigger: lastApplied,
      lastResult: lastResult,
      lastIoErr: lastIoErr,
      lastAttemptAt: DateTime.now(),
      message: 'Timeout after ${effectiveTimeoutMs}ms',
    );
  }

  Future<List<int>> _readHoldingWithRetry({
    required int startAddress,
    required int count,
    required String operationName,
    int? maxAttempts,
  }) async {
    final attempts = maxAttempts ?? _transportAttemptCount;
    if (count < 1) {
      throw RangeError.range(count, 1, null, 'count');
    }
    if (count > 125) {
      final regs = <int>[];
      var offset = 0;
      while (offset < count) {
        final chunkCount = (count - offset) > 125 ? 125 : (count - offset);
        final chunk = await _readHoldingWithRetry(
          startAddress: startAddress + offset,
          count: chunkCount,
          operationName: '$operationName+$offset',
          maxAttempts: attempts,
        );
        if (chunk.length != chunkCount) {
          throw StateError(
            'Short read: op=$operationName offset=$offset '
            'expected=$chunkCount actual=${chunk.length}',
          );
        }
        regs.addAll(chunk);
        offset += chunkCount;
      }
      return regs;
    }
    Object? lastFailure;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        return await _client.readHoldingRegisters(
          unitId: config.deviceConnection.unitId,
          startAddress: startAddress,
          count: count,
        );
      } catch (e) {
        lastFailure = e;
        if (!_isRetryableTransportError(e)) {
          rethrow;
        }
        _addClientTrace(
          'read retry op=$operationName attempt=${attempt + 1}/$attempts: $e',
        );
        if (attempt + 1 < attempts) {
          await Future<void>.delayed(
            Duration(milliseconds: config.timeouts.retryBackoffMs),
          );
        }
      }
    }
    throw lastFailure ??
        StateError('Read failed without error: operation=$operationName');
  }

  Future<void> _writeSingleWithRetry({
    required int address,
    required int value,
    required String operationName,
    int? maxAttempts,
  }) async {
    final attempts = maxAttempts ?? _transportAttemptCount;
    Object? lastFailure;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        await _client.writeSingleRegister(
          unitId: config.deviceConnection.unitId,
          address: address,
          value: value,
        );
        return;
      } catch (e) {
        lastFailure = e;
        if (!_isRetryableTransportError(e)) {
          rethrow;
        }
        _addClientTrace(
          'write single retry op=$operationName attempt=${attempt + 1}/$attempts: $e',
        );
        if (attempt + 1 < attempts) {
          await Future<void>.delayed(
            Duration(milliseconds: config.timeouts.retryBackoffMs),
          );
        }
      }
    }
    throw lastFailure ??
        StateError('Write failed without error: operation=$operationName');
  }

  Future<void> _writeMultipleWithRetry({
    required int startAddress,
    required List<int> values,
    required String operationName,
    int? maxAttempts,
  }) async {
    final attempts = maxAttempts ?? _transportAttemptCount;
    Object? lastFailure;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        await _client.writeMultipleRegisters(
          unitId: config.deviceConnection.unitId,
          startAddress: startAddress,
          values: values,
        );
        return;
      } catch (e) {
        lastFailure = e;
        if (!_isRetryableTransportError(e)) {
          rethrow;
        }
        _addClientTrace(
          'write multiple retry op=$operationName attempt=${attempt + 1}/$attempts: $e',
        );
        if (attempt + 1 < attempts) {
          await Future<void>.delayed(
            Duration(milliseconds: config.timeouts.retryBackoffMs),
          );
        }
      }
    }
    throw lastFailure ??
        StateError('Write failed without error: operation=$operationName');
  }

  Future<void> _ensureMapCompatible() async {
    if (compatibility.state == ScadaCompatibilityState.mapIncompatible) {
      throw StateError(compatibility.message);
    }
    if (directorySnapshot == null || deviceTopologyMetadata == null) {
      await refreshSession();
    }
    if (compatibility.state == ScadaCompatibilityState.mapIncompatible) {
      throw StateError(compatibility.message);
    }
  }

  int get _transportAttemptCount {
    final retryCount = config.transport.retryCount;
    return retryCount < 0 ? 1 : retryCount + 1;
  }

  int get _effectiveSchedulePollIntervalMs {
    final configured = config.pollIntervals.commandPollMs;
    if (configured < _minSchedulePollIntervalMs) {
      return _minSchedulePollIntervalMs;
    }
    if (configured > _maxSchedulePollIntervalMs) {
      return _maxSchedulePollIntervalMs;
    }
    return configured;
  }

  Future<T> _runWithPollingPause<T>(
    String reason,
    Future<T> Function() action,
  ) async {
    final shouldPause = config.featureFlags.pausePollingDuringWriteWorkflows;
    if (shouldPause) {
      _pollingPauseDepth += 1;
      _addClientTrace(
        'polling paused reason=$reason depth=$_pollingPauseDepth',
      );
      if (!_disposed) {
        notifyListeners();
      }
      while (polling) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
    try {
      return await action();
    } finally {
      if (shouldPause) {
        _pollingPauseDepth -= 1;
        _addClientTrace(
          'polling resumed reason=$reason depth=$_pollingPauseDepth',
        );
        if (_pollingPauseDepth <= 0) {
          _pollingPauseDepth = 0;
          if (!_disposed) {
            unawaited(refreshSession());
            unawaited(_pollTick());
          }
        }
        if (!_disposed) {
          notifyListeners();
        }
      }
    }
  }

  Future<int> _nextRtcSetToken() async {
    final regs = await _readHoldingWithRetry(
      startAddress:
          _registerMap.directoryBase + _registerMap.rtcSetAppliedTokenOffset,
      count: 1,
      operationName: 'rtc_set_token_precheck',
      maxAttempts: 1,
    );
    var next = ((_topologySubmitToken + 1) & 0xFFFF);
    if (next == 0) {
      next = 1;
    }
    if (regs.isNotEmpty && next == (regs[0] & 0xFFFF)) {
      next = (next + 1) & 0xFFFF;
      if (next == 0) {
        next = 1;
      }
    }
    _topologySubmitToken = next;
    return next;
  }

  int _joinU32(int hi, int lo) => ((hi & 0xFFFF) << 16) | (lo & 0xFFFF);

  int _toSignedI32(int hi, int lo) {
    final value = _joinU32(hi, lo);
    return value >= 0x80000000 ? value - 0x100000000 : value;
  }

  int _nextLightingTrigger({required int lastAppliedTrigger}) {
    var next = (_lightingTriggerCounter + 1) & 0xFFFF;
    if (next == 0) {
      next = 1;
    }
    if (next == (lastAppliedTrigger & 0xFFFF)) {
      next = (next + 1) & 0xFFFF;
      if (next == 0) {
        next = 1;
      }
    }
    _lightingTriggerCounter = next;
    return next;
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _connectionSub?.cancel();
    unawaited(_client.dispose());
    super.dispose();
  }

  List<ModuleSummary> _buildModuleSummaries() {
    final resolver = topologyResolver;
    if (resolver == null) {
      return const <ModuleSummary>[];
    }
    return resolver.manifest.modules
        .map(
          (module) => ModuleSummary(
            module: module,
            pointCount: resolver.pointsForModule(module.moduleId).length,
            scheduleAvailable: resolver.hasScheduleContract(module.moduleId),
          ),
        )
        .toList(growable: false);
  }

  List<RuntimeModuleTelemetryView> _buildRuntimeTelemetryModules() {
    final grouped = <int, List<RuntimeTelemetryPointView>>{};
    for (final entry in _telemetryByPublishIndex.entries) {
      final moduleId = entry.value.moduleId;
      if (moduleId <= 0) {
        continue;
      }
      grouped
          .putIfAbsent(moduleId, () => <RuntimeTelemetryPointView>[])
          .add(
            RuntimeTelemetryPointView(
              publishIndex: entry.key,
              telemetry: entry.value,
            ),
          );
    }
    final moduleIds = grouped.keys.toList()..sort();
    return moduleIds
        .map((moduleId) {
          final points = grouped[moduleId]!
            ..sort(
              (left, right) => left.publishIndex.compareTo(right.publishIndex),
            );
          final kind = _runtimeModuleKind(moduleId);
          return RuntimeModuleTelemetryView(
            moduleId: moduleId,
            kind: kind,
            title: _runtimeModuleTitle(moduleId, kind),
            subtitle: 'runtime rows=${points.length}  module_id=$moduleId',
            points: List<RuntimeTelemetryPointView>.unmodifiable(points),
          );
        })
        .toList(growable: false);
  }

  void _rebuildScheduleStates() {
    final resolver = topologyResolver;
    if (resolver == null) {
      _scheduleStatusByModuleId.clear();
      return;
    }
    final validModuleIds = resolver.zoneModules
        .map((item) => item.moduleId)
        .toSet();
    _scheduleStatusByModuleId.removeWhere(
      (moduleId, _) => !validModuleIds.contains(moduleId),
    );
    for (final module in resolver.zoneModules) {
      final existing = _scheduleStatusByModuleId[module.moduleId];
      final draft = _draftForModule(
        module: module,
        currentDraft: existing?.draft,
      );
      final status =
          existing?.copyWith(
            moduleId: module.moduleId,
            zoneId: module.zoneId,
            slaveId: module.slaveId,
            draft: draft,
          ) ??
          LightingScheduleStatus.initial(
            moduleId: module.moduleId,
            zoneId: module.zoneId,
            slaveId: module.slaveId,
          ).copyWith(draft: draft);
      _scheduleStatusByModuleId[module.moduleId] = status;
    }
  }

  LightingScheduleDraft _draftForModule({
    required TopologyModule module,
    LightingScheduleDraft? currentDraft,
  }) {
    final baseDraft =
        currentDraft ?? _persistedLightingDraftByModuleId[module.moduleId];
    return (baseDraft ??
            LightingScheduleDraft.initial(
              moduleId: module.moduleId,
              zoneId: module.zoneId,
              slaveId: module.slaveId,
            ))
        .rebind(
          moduleId: module.moduleId,
          zoneId: module.zoneId,
          slaveId: module.slaveId,
        );
  }

  Future<void> _persistLastSentLightingDraft({
    required TopologyModule module,
    required LightingScheduleDraft draft,
  }) async {
    final persistedDraft = draft.rebind(
      moduleId: module.moduleId,
      zoneId: module.zoneId,
      slaveId: module.slaveId,
    );
    _persistedLightingDraftByModuleId[module.moduleId] = persistedDraft;
    try {
      await _configStore.saveLightingDrafts(_persistedLightingDraftByModuleId);
    } catch (e) {
      _addClientTrace(
        'schedule cache save failed module=${module.moduleId}: $e',
      );
    }
  }

  void _recomputeCompatibility() {
    final directory = directorySnapshot;
    final device = deviceTopologyMetadata;
    final manifest = topologySnapshot.manifest;
    if (directory == null || device == null) {
      if (topologySnapshot.manifestError != null) {
        compatibility = CompatibilityStatus(
          state: ScadaCompatibilityState.localTopologyMissing,
          message: topologySnapshot.manifestError!,
        );
      }
      return;
    }
    if (!directory.topologyActive || !device.isActive) {
      compatibility = const CompatibilityStatus(
        state: ScadaCompatibilityState.deviceTopologyInactive,
        message:
            'Device topology is inactive. Only bootstrap and upload are allowed.',
      );
      return;
    }
    if (manifest == null) {
      compatibility = CompatibilityStatus(
        state: ScadaCompatibilityState.localTopologyMissing,
        message:
            topologySnapshot.manifestError ??
            'Local topology manifest is missing.',
      );
      return;
    }
    final deviceSchema = '${device.versionMajor}.${device.versionMinor}';
    if (manifest.generation != device.activeGeneration ||
        manifest.schemaVersion != deviceSchema) {
      compatibility = CompatibilityStatus(
        state: ScadaCompatibilityState.topologyGenerationMismatch,
        message:
            'Topology mismatch: local generation=${manifest.generation} '
            'schema=${manifest.schemaVersion}, '
            'device generation=${device.activeGeneration} schema=$deviceSchema.',
      );
      return;
    }
    compatibility = CompatibilityStatus(
      state: ScadaCompatibilityState.ready,
      message:
          'Ready. generation=${manifest.generation}, '
          'device_size=${device.activeSizeBytes} bytes.',
    );
  }

  String lightingResultLabel(int code) {
    switch (code & 0xFFFF) {
      case _scheduleResultIdle:
        return 'idle';
      case _scheduleResultQueued:
        return 'queued';
      case _scheduleResultApplied:
        return 'applied';
      case 10:
        return 'reject bounds';
      case 11:
        return 'reject topology';
      case 12:
        return 'reject fc';
      case 13:
        return 'reject busy';
      case 14:
        return 'reject partial';
      case 15:
        return 'transport fail';
      case 16:
        return 'ack fail';
      case 1301:
        return 'ack status fail';
      case 1302:
        return 'version mismatch';
      case 1303:
        return 'invalid cmd kind';
      case 1304:
        return 'invalid schedule';
      case 1305:
        return 'topology contract';
      case 1306:
        return 'transport timeout';
      default:
        return 'unknown($code)';
    }
  }

  String lightingIoErrLabel(int code) {
    switch (code & 0xFFFF) {
      case 0:
        return 'none';
      case 1:
        return 'timeout';
      case 2:
        return 'crc';
      case 3:
        return 'frame';
      case 4:
        return 'uart';
      default:
        return 'unknown($code)';
    }
  }

  String _qualityLabel(int quality) {
    switch (quality) {
      case 0:
        return 'OK';
      case 1:
        return 'STALE';
      case 2:
        return 'FAULT';
      case 3:
        return 'OFFLINE';
      default:
        return 'Q$quality';
    }
  }

  bool _isRetryableTransportError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('timeout') ||
        message.contains('not connected') ||
        message.contains('disconnected') ||
        message.contains('connection reset') ||
        message.contains('broken pipe') ||
        message.contains('socketexception') ||
        message.contains('connection refused');
  }

  double _toFloat32FromHiLo(int hi, int lo) {
    final raw = ((hi & 0xFFFF) << 16) | (lo & 0xFFFF);
    final data = ByteData(4)..setUint32(0, raw, Endian.big);
    return data.getFloat32(0, Endian.big);
  }

  RuntimeModuleKind _runtimeModuleKind(int moduleId) {
    if (moduleId >= 100 && moduleId < 200) {
      return RuntimeModuleKind.zone;
    }
    if (moduleId >= 200 && moduleId < 300) {
      return RuntimeModuleKind.weather;
    }
    return RuntimeModuleKind.other;
  }

  String _runtimeModuleTitle(int moduleId, RuntimeModuleKind kind) {
    switch (kind) {
      case RuntimeModuleKind.zone:
        return 'Zone module $moduleId';
      case RuntimeModuleKind.weather:
        return 'Weather module $moduleId';
      case RuntimeModuleKind.other:
        return 'Module $moduleId';
    }
  }

  void _addClientTrace(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '$timestamp $message';
    _clientTrace.insert(0, line);
    if (_clientTrace.length > 120) {
      _clientTrace.removeRange(120, _clientTrace.length);
    }
    unawaited(_logger.logClientEvent(message));
  }
}

class _PollingTransportAbort implements Exception {
  const _PollingTransportAbort(this.message);

  final String message;

  @override
  String toString() => message;
}

class _WeatherSemantic {
  const _WeatherSemantic({
    required this.semanticName,
    required this.label,
    required this.unit,
    required this.decimals,
  });

  final String semanticName;
  final String label;
  final String unit;
  final int decimals;
}

const List<_WeatherSemantic> _weatherSemantics = <_WeatherSemantic>[
  _WeatherSemantic(
    semanticName: 'outside_temperature',
    label: 'Outside temperature',
    unit: 'C',
    decimals: 1,
  ),
  _WeatherSemantic(
    semanticName: 'outside_humidity',
    label: 'Outside humidity',
    unit: '%',
    decimals: 1,
  ),
  _WeatherSemantic(
    semanticName: 'wind_speed',
    label: 'Wind speed',
    unit: 'm/s',
    decimals: 1,
  ),
  _WeatherSemantic(
    semanticName: 'wind_direction',
    label: 'Wind direction',
    unit: 'deg',
    decimals: 0,
  ),
  _WeatherSemantic(
    semanticName: 'rain_flag',
    label: 'Rain flag',
    unit: '',
    decimals: 0,
  ),
  _WeatherSemantic(
    semanticName: 'solar_radiation',
    label: 'Solar radiation',
    unit: 'W/m2',
    decimals: 0,
  ),
  _WeatherSemantic(
    semanticName: 'barometric_pressure',
    label: 'Barometric pressure',
    unit: 'hPa',
    decimals: 1,
  ),
];

const List<_WeatherSemantic> _lightingFeedbackSemantics = <_WeatherSemantic>[
  _WeatherSemantic(
    semanticName: 'current_dli',
    label: 'Current DLI',
    unit: '',
    decimals: 2,
  ),
  _WeatherSemantic(
    semanticName: 'light_output',
    label: 'Light output',
    unit: '%',
    decimals: 0,
  ),
  _WeatherSemantic(
    semanticName: 'light_status_bits',
    label: 'Status bits',
    unit: '',
    decimals: 0,
  ),
];

int maxU16(int a, int b) => (a > b ? a : b) & 0xFFFF;
