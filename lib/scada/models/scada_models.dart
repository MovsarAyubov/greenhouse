import '../services/modbus_tcp_client.dart';
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

  DeviceConnectionConfig copyWith({
    String? host,
    int? port,
    int? unitId,
  }) {
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
    required this.commandPollMs,
    required this.uploadPollMs,
  });

  final int telemetryMs;
  final int commandPollMs;
  final int uploadPollMs;

  PollIntervalsConfig copyWith({
    int? telemetryMs,
    int? commandPollMs,
    int? uploadPollMs,
  }) {
    return PollIntervalsConfig(
      telemetryMs: telemetryMs ?? this.telemetryMs,
      commandPollMs: commandPollMs ?? this.commandPollMs,
      uploadPollMs: uploadPollMs ?? this.uploadPollMs,
    );
  }
}

class TimeoutConfig {
  const TimeoutConfig({
    required this.connectMs,
    required this.responseMs,
    required this.commandMs,
    required this.uploadChunkMs,
    required this.uploadCommitMs,
  });

  final int connectMs;
  final int responseMs;
  final int commandMs;
  final int uploadChunkMs;
  final int uploadCommitMs;

  TimeoutConfig copyWith({
    int? connectMs,
    int? responseMs,
    int? commandMs,
    int? uploadChunkMs,
    int? uploadCommitMs,
  }) {
    return TimeoutConfig(
      connectMs: connectMs ?? this.connectMs,
      responseMs: responseMs ?? this.responseMs,
      commandMs: commandMs ?? this.commandMs,
      uploadChunkMs: uploadChunkMs ?? this.uploadChunkMs,
      uploadCommitMs: uploadCommitMs ?? this.uploadCommitMs,
    );
  }
}

class FeatureFlagsConfig {
  const FeatureFlagsConfig({
    required this.allowTelemetryOnGenerationMismatch,
    required this.showUnsupportedPoints,
  });

  final bool allowTelemetryOnGenerationMismatch;
  final bool showUnsupportedPoints;

  FeatureFlagsConfig copyWith({
    bool? allowTelemetryOnGenerationMismatch,
    bool? showUnsupportedPoints,
  }) {
    return FeatureFlagsConfig(
      allowTelemetryOnGenerationMismatch:
          allowTelemetryOnGenerationMismatch ??
          this.allowTelemetryOnGenerationMismatch,
      showUnsupportedPoints:
          showUnsupportedPoints ?? this.showUnsupportedPoints,
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
    required this.featureFlags,
  });

  final DeviceConnectionConfig deviceConnection;
  final ModbusAddressMode addressMode;
  final String localTopologyManifestPath;
  final String localTopologyBlobPath;
  final String semanticCatalogPath;
  final PollIntervalsConfig pollIntervals;
  final TimeoutConfig timeouts;
  final FeatureFlagsConfig featureFlags;

  ScadaConfig copyWith({
    DeviceConnectionConfig? deviceConnection,
    ModbusAddressMode? addressMode,
    String? localTopologyManifestPath,
    String? localTopologyBlobPath,
    String? semanticCatalogPath,
    PollIntervalsConfig? pollIntervals,
    TimeoutConfig? timeouts,
    FeatureFlagsConfig? featureFlags,
  }) {
    return ScadaConfig(
      deviceConnection: deviceConnection ?? this.deviceConnection,
      addressMode: addressMode ?? this.addressMode,
      localTopologyManifestPath:
          localTopologyManifestPath ?? this.localTopologyManifestPath,
      localTopologyBlobPath: localTopologyBlobPath ?? this.localTopologyBlobPath,
      semanticCatalogPath: semanticCatalogPath ?? this.semanticCatalogPath,
      pollIntervals: pollIntervals ?? this.pollIntervals,
      timeouts: timeouts ?? this.timeouts,
      featureFlags: featureFlags ?? this.featureFlags,
    );
  }

  static ScadaConfig defaults() => ScadaConfig(
    deviceConnection: const DeviceConnectionConfig(
      host: '192.168.50.20',
      port: 502,
      unitId: 1,
    ),
    addressMode: ModbusAddressMode.zeroBased,
    localTopologyManifestPath: '',
    localTopologyBlobPath: '',
    semanticCatalogPath: '',
    pollIntervals: const PollIntervalsConfig(
      telemetryMs: 5000,
      commandPollMs: 500,
      uploadPollMs: 100,
    ),
    timeouts: const TimeoutConfig(
      connectMs: 4000,
      responseMs: 1800,
      commandMs: 25000,
      uploadChunkMs: 3000,
      uploadCommitMs: 15000,
    ),
    featureFlags: const FeatureFlagsConfig(
      allowTelemetryOnGenerationMismatch: true,
      showUnsupportedPoints: true,
    ),
  );
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

enum RuntimeModuleKind {
  zone,
  weather,
  other,
}

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
