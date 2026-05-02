import '../services/modbus_tcp_client.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'topology_models.dart';

class DeviceConnectionConfig {
  const DeviceConnectionConfig({
    required this.host,
    required this.port,
    required this.unitId,
  });

  final String host;
  final int port;
  final int unitId;

  DeviceConnectionConfig copyWith({String? host, int? port, int? unitId}) {
    return DeviceConnectionConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      unitId: unitId ?? this.unitId,
    );
  }
}

class PollIntervalsConfig {
  const PollIntervalsConfig({
    required this.telemetryMs,
    required this.diagMs,
    required this.commandPollMs,
    required this.uploadPollMs,
  });

  final int telemetryMs;
  final int diagMs;
  final int commandPollMs;
  final int uploadPollMs;

  PollIntervalsConfig copyWith({
    int? telemetryMs,
    int? diagMs,
    int? commandPollMs,
    int? uploadPollMs,
  }) {
    return PollIntervalsConfig(
      telemetryMs: telemetryMs ?? this.telemetryMs,
      diagMs: diagMs ?? this.diagMs,
      commandPollMs: commandPollMs ?? this.commandPollMs,
      uploadPollMs: uploadPollMs ?? this.uploadPollMs,
    );
  }
}

class TimeoutConfig {
  const TimeoutConfig({
    required this.connectMs,
    required this.responseMs,
    required this.retryBackoffMs,
    required this.commandMs,
    required this.uploadChunkMs,
    required this.uploadCommitMs,
  });

  final int connectMs;
  final int responseMs;
  final int retryBackoffMs;
  final int commandMs;
  final int uploadChunkMs;
  final int uploadCommitMs;

  TimeoutConfig copyWith({
    int? connectMs,
    int? responseMs,
    int? retryBackoffMs,
    int? commandMs,
    int? uploadChunkMs,
    int? uploadCommitMs,
  }) {
    return TimeoutConfig(
      connectMs: connectMs ?? this.connectMs,
      responseMs: responseMs ?? this.responseMs,
      retryBackoffMs: retryBackoffMs ?? this.retryBackoffMs,
      commandMs: commandMs ?? this.commandMs,
      uploadChunkMs: uploadChunkMs ?? this.uploadChunkMs,
      uploadCommitMs: uploadCommitMs ?? this.uploadCommitMs,
    );
  }
}

class TransportConfig {
  const TransportConfig({required this.retryCount});

  final int retryCount;

  TransportConfig copyWith({int? retryCount}) {
    return TransportConfig(retryCount: retryCount ?? this.retryCount);
  }
}

class FeatureFlagsConfig {
  const FeatureFlagsConfig({
    required this.allowTelemetryOnGenerationMismatch,
    required this.showUnsupportedPoints,
    required this.pausePollingDuringWriteWorkflows,
  });

  final bool allowTelemetryOnGenerationMismatch;
  final bool showUnsupportedPoints;
  final bool pausePollingDuringWriteWorkflows;

  FeatureFlagsConfig copyWith({
    bool? allowTelemetryOnGenerationMismatch,
    bool? showUnsupportedPoints,
    bool? pausePollingDuringWriteWorkflows,
  }) {
    return FeatureFlagsConfig(
      allowTelemetryOnGenerationMismatch:
          allowTelemetryOnGenerationMismatch ??
          this.allowTelemetryOnGenerationMismatch,
      showUnsupportedPoints:
          showUnsupportedPoints ?? this.showUnsupportedPoints,
      pausePollingDuringWriteWorkflows:
          pausePollingDuringWriteWorkflows ??
          this.pausePollingDuringWriteWorkflows,
    );
  }
}

class ScadaConfig {
  const ScadaConfig({
    required this.deviceConnection,
    required this.addressMode,
    required this.localTopologyManifestPath,
    required this.localTopologyBlobPath,
    required this.semanticCatalogPath,
    required this.pollIntervals,
    required this.timeouts,
    required this.transport,
    required this.featureFlags,
  });

  final DeviceConnectionConfig deviceConnection;
  final ModbusAddressMode addressMode;
  final String localTopologyManifestPath;
  final String localTopologyBlobPath;
  final String semanticCatalogPath;
  final PollIntervalsConfig pollIntervals;
  final TimeoutConfig timeouts;
  final TransportConfig transport;
  final FeatureFlagsConfig featureFlags;

  ScadaConfig copyWith({
    DeviceConnectionConfig? deviceConnection,
    ModbusAddressMode? addressMode,
    String? localTopologyManifestPath,
    String? localTopologyBlobPath,
    String? semanticCatalogPath,
    PollIntervalsConfig? pollIntervals,
    TimeoutConfig? timeouts,
    TransportConfig? transport,
    FeatureFlagsConfig? featureFlags,
  }) {
    return ScadaConfig(
      deviceConnection: deviceConnection ?? this.deviceConnection,
      addressMode: addressMode ?? this.addressMode,
      localTopologyManifestPath:
          localTopologyManifestPath ?? this.localTopologyManifestPath,
      localTopologyBlobPath:
          localTopologyBlobPath ?? this.localTopologyBlobPath,
      semanticCatalogPath: semanticCatalogPath ?? this.semanticCatalogPath,
      pollIntervals: pollIntervals ?? this.pollIntervals,
      timeouts: timeouts ?? this.timeouts,
      transport: transport ?? this.transport,
      featureFlags: featureFlags ?? this.featureFlags,
    );
  }

  static ScadaConfig defaults() => ScadaConfig(
    deviceConnection: DeviceConnectionConfig(
      host: _envString('SCADA_HOST', '192.168.50.20'),
      port: _envInt('SCADA_PORT', 502),
      unitId: _envInt('SCADA_UNIT_ID', 1),
    ),
    addressMode: _envAddressMode('SCADA_ADDRESS_MODE'),
    localTopologyManifestPath: _envString('SCADA_TOPOLOGY_MANIFEST_PATH', ''),
    localTopologyBlobPath: _envString('SCADA_TOPOLOGY_BLOB_PATH', ''),
    semanticCatalogPath: _envString('SCADA_SEMANTIC_CATALOG_PATH', ''),
    pollIntervals: PollIntervalsConfig(
      telemetryMs: _envInt('SCADA_POLL_TELEMETRY_MS', 5000),
      diagMs: _envInt('SCADA_POLL_DIAG_MS', 30000),
      commandPollMs: _envInt('SCADA_POLL_COMMAND_MS', 500),
      uploadPollMs: _envInt('SCADA_POLL_UPLOAD_MS', 100),
    ),
    timeouts: TimeoutConfig(
      connectMs: _envInt('SCADA_TIMEOUT_CONNECT_MS', 4000),
      responseMs: _envInt('SCADA_TIMEOUT_RESPONSE_MS', 1000),
      retryBackoffMs: _envInt('SCADA_TIMEOUT_RETRY_BACKOFF_MS', 100),
      commandMs: _envInt('SCADA_TIMEOUT_COMMAND_MS', 25000),
      uploadChunkMs: _envInt('SCADA_TIMEOUT_UPLOAD_CHUNK_MS', 3000),
      uploadCommitMs: _envInt('SCADA_TIMEOUT_UPLOAD_COMMIT_MS', 15000),
    ),
    transport: TransportConfig(retryCount: _envInt('SCADA_RETRY_COUNT', 0)),
    featureFlags: FeatureFlagsConfig(
      allowTelemetryOnGenerationMismatch: _envBool(
        'SCADA_ALLOW_TELEMETRY_ON_GENERATION_MISMATCH',
        true,
      ),
      showUnsupportedPoints: _envBool('SCADA_SHOW_UNSUPPORTED_POINTS', true),
      pausePollingDuringWriteWorkflows: _envBool(
        'SCADA_PAUSE_POLLING_DURING_WRITES',
        true,
      ),
    ),
  );
}

String _envString(String key, String fallback) {
  final value = dotenv.maybeGet(key);
  if (value == null || value.trim().isEmpty) {
    return fallback;
  }
  return value.trim();
}

int _envInt(String key, int fallback) {
  final value = dotenv.maybeGet(key);
  if (value == null) {
    return fallback;
  }
  return int.tryParse(value.trim()) ?? fallback;
}

bool _envBool(String key, bool fallback) {
  final value = dotenv.maybeGet(key);
  if (value == null) {
    return fallback;
  }
  final norm = value.trim().toLowerCase();
  if (norm == '1' || norm == 'true' || norm == 'yes' || norm == 'on') {
    return true;
  }
  if (norm == '0' || norm == 'false' || norm == 'no' || norm == 'off') {
    return false;
  }
  return fallback;
}

ModbusAddressMode _envAddressMode(String key) {
  final value = dotenv.maybeGet(key)?.trim().toLowerCase();
  switch (value) {
    case 'scada_4xxxx':
    case 'style4xxxx':
    case '4xxxx':
      return ModbusAddressMode.style4xxxx;
    default:
      return ModbusAddressMode.zeroBased;
  }
}

class PointTelemetryValue {
  const PointTelemetryValue({
    required this.value,
    required this.quality,
    required this.ageSec,
    required this.moduleId,
    required this.flags,
  });

  final double value;
  final int quality;
  final int ageSec;
  final int moduleId;
  final int flags;

  bool get hasValidFlag => (flags & 0x0001) != 0;
  bool get isUsable => hasValidFlag && quality != 3;
}

class ResolvedPointValue {
  const ResolvedPointValue({
    required this.point,
    required this.telemetry,
    required this.pointContractState,
    required this.statusMessage,
  });

  final TopologyPoint point;
  final PointTelemetryValue? telemetry;
  final ScadaCompatibilityState pointContractState;
  final String statusMessage;

  bool get isSupported =>
      pointContractState != ScadaCompatibilityState.pointContractMissing;
}

class SlaveStatusSnapshot {
  const SlaveStatusSnapshot({
    required this.statusFlags,
    required this.lastOkAgeSec,
    required this.errTimeout,
    required this.errCrc,
    required this.errException,
    required this.dataVersion,
    required this.validMask,
    required this.outStateMask,
  });

  final int statusFlags;
  final int lastOkAgeSec;
  final int errTimeout;
  final int errCrc;
  final int errException;
  final int dataVersion;
  final int validMask;
  final int outStateMask;

  bool get online => (statusFlags & 0x0001) != 0;
  bool get stale => (statusFlags & 0x0002) != 0;
}

class DiagnosticsSnapshot {
  const DiagnosticsSnapshot({
    required this.bootCount,
    required this.powerOnCount,
    required this.errorHandlerCount,
    required this.watchdogMissCount,
    required this.faultResetCount,
    required this.lastEventCode,
    required this.lastResetReason,
    required this.lastErrorCode,
    required this.modbusTimeout0,
    required this.modbusTimeout1,
    required this.tcpAcceptErrCount,
    required this.tcpRecvTimeoutCount,
    required this.tcpStaleCloseCount,
    required this.tcpMalformedMbapCount,
    required this.tcpSendErrCount,
    required this.tcpLastErr,
  });

  final int bootCount;
  final int powerOnCount;
  final int errorHandlerCount;
  final int watchdogMissCount;
  final int faultResetCount;
  final int lastEventCode;
  final int lastResetReason;
  final int lastErrorCode;
  final int modbusTimeout0;
  final int modbusTimeout1;
  final int tcpAcceptErrCount;
  final int tcpRecvTimeoutCount;
  final int tcpStaleCloseCount;
  final int tcpMalformedMbapCount;
  final int tcpSendErrCount;
  final int tcpLastErr;
}

class ModuleSummary {
  const ModuleSummary({
    required this.module,
    required this.pointCount,
    required this.scheduleAvailable,
  });

  final TopologyModule module;
  final int pointCount;
  final bool scheduleAvailable;
}

class SemanticFieldView {
  const SemanticFieldView({
    required this.semanticName,
    required this.label,
    required this.unit,
    required this.decimals,
    required this.point,
    required this.telemetry,
    required this.state,
    required this.message,
  });

  final String semanticName;
  final String label;
  final String unit;
  final int decimals;
  final TopologyPoint? point;
  final PointTelemetryValue? telemetry;
  final ScadaCompatibilityState state;
  final String message;
}

enum RuntimeModuleKind { zone, weather, other }

class RuntimeTelemetryPointView {
  const RuntimeTelemetryPointView({
    required this.publishIndex,
    required this.telemetry,
  });

  final int publishIndex;
  final PointTelemetryValue telemetry;
}

class RuntimeModuleTelemetryView {
  const RuntimeModuleTelemetryView({
    required this.moduleId,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.points,
  });

  final int moduleId;
  final RuntimeModuleKind kind;
  final String title;
  final String subtitle;
  final List<RuntimeTelemetryPointView> points;
}

class AlarmEntry {
  const AlarmEntry({
    required this.id,
    required this.zoneId,
    required this.message,
    required this.raisedAt,
  });

  final String id;
  final int zoneId;
  final String message;
  final DateTime raisedAt;
}
