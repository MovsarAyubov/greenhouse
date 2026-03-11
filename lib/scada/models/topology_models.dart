enum ScadaCompatibilityState {
  ready,
  mapIncompatible,
  deviceTopologyInactive,
  localTopologyMissing,
  topologyGenerationMismatch,
  commandContractMissing,
  pointContractMissing,
}

class CompatibilityStatus {
  const CompatibilityStatus({
    required this.state,
    required this.message,
  });

  final ScadaCompatibilityState state;
  final String message;

  bool get isReady => state == ScadaCompatibilityState.ready;
}

class RegisterDirectorySnapshot {
  const RegisterDirectorySnapshot({
    required this.mapVersion,
    required this.mapFlags,
    required this.pointCount,
    required this.pointStride,
    required this.pointsBase,
    required this.slaveStatusBase,
    required this.cmdBase,
    required this.maxPoints,
    required this.cmdBlockSize,
    required this.statusBlockSize,
    required this.rtcHour,
    required this.rtcMinute,
  });

  final int mapVersion;
  final int mapFlags;
  final int pointCount;
  final int pointStride;
  final int pointsBase;
  final int slaveStatusBase;
  final int cmdBase;
  final int maxPoints;
  final int cmdBlockSize;
  final int statusBlockSize;
  final int rtcHour;
  final int rtcMinute;

  bool get dirValid => (mapFlags & 0x0001) != 0;
  bool get topologyActive => (mapFlags & 0x0002) != 0;
}

class DeviceTopologyMetadata {
  const DeviceTopologyMetadata({
    required this.flags,
    required this.versionMajor,
    required this.versionMinor,
    required this.activeGeneration,
    required this.activeSizeBytes,
    required this.resultCode,
    required this.resultToken,
  });

  final int flags;
  final int versionMajor;
  final int versionMinor;
  final int activeGeneration;
  final int activeSizeBytes;
  final int resultCode;
  final int resultToken;

  bool get isActive => (flags & 0x0001) != 0;
  bool get commitInProgress => (flags & 0x0002) != 0;
}

class RegisterBootstrapResult {
  const RegisterBootstrapResult({
    required this.directory,
    required this.topologyMetadata,
    required this.contractError,
    required this.bootstrapError,
  });

  final RegisterDirectorySnapshot? directory;
  final DeviceTopologyMetadata? topologyMetadata;
  final String? contractError;
  final String? bootstrapError;

  bool get isMapCompatible => contractError == null && directory != null;
}

class TopologyManifest {
  const TopologyManifest({
    required this.schemaVersion,
    required this.generation,
    required this.topologyId,
    required this.modules,
    required this.requests,
    required this.points,
    required this.commands,
    required this.policies,
  });

  final String schemaVersion;
  final int generation;
  final int topologyId;
  final List<TopologyModule> modules;
  final List<TopologyRequest> requests;
  final List<TopologyPoint> points;
  final List<TopologyCommand> commands;
  final List<TopologyPolicy> policies;

  factory TopologyManifest.fromJson(Map<String, dynamic> json) {
    final schemaVersion =
        (json['schema_version'] as String?) ??
        '${_readInt(json, 'ver_major', defaultValue: 2)}.'
            '${_readInt(json, 'ver_minor', defaultValue: 0)}';
    return TopologyManifest(
      schemaVersion: schemaVersion,
      generation: _readInt(json, 'generation'),
      topologyId: _readInt(json, 'topology_id'),
      modules: _readList(json, 'modules')
          .map((item) => TopologyModule.fromJson(item))
          .toList(growable: false),
      requests: _readList(json, 'requests')
          .map((item) => TopologyRequest.fromJson(item))
          .toList(growable: false),
      points: _readList(json, 'points')
          .map((item) => TopologyPoint.fromJson(item))
          .toList(growable: false),
      commands: _readList(json, 'commands')
          .map((item) => TopologyCommand.fromJson(item))
          .toList(growable: false),
      policies: _readList(json, 'policies')
          .map((item) => TopologyPolicy.fromJson(item))
          .toList(growable: false),
    );
  }
}

class TopologyModule {
  const TopologyModule({
    required this.moduleId,
    required this.moduleType,
    required this.busType,
    required this.busIndex,
    required this.slaveId,
    required this.zoneId,
    required this.capabilityMask,
    required this.userParam0,
    required this.userParam1,
  });

  final int moduleId;
  final int moduleType;
  final int busType;
  final int busIndex;
  final int slaveId;
  final int zoneId;
  final int capabilityMask;
  final int userParam0;
  final int userParam1;

  factory TopologyModule.fromJson(Map<String, dynamic> json) {
    return TopologyModule(
      moduleId: _readInt(json, 'module_id'),
      moduleType: _readInt(json, 'module_type'),
      busType: _readInt(json, 'bus_type'),
      busIndex: _readInt(json, 'bus_index'),
      slaveId: _readInt(json, 'slave_id'),
      zoneId: _readInt(json, 'zone_id'),
      capabilityMask: _readInt(json, 'capability_mask', defaultValue: 0),
      userParam0: _readInt(json, 'user_param0', defaultValue: 0),
      userParam1: _readInt(json, 'user_param1', defaultValue: 0),
    );
  }

  bool get isZone => moduleType == 1;
  bool get isWeather => moduleType == 2;

  String get title {
    switch (moduleType) {
      case 1:
        return zoneId > 0 ? 'Zone $zoneId' : 'Zone module $moduleId';
      case 2:
        return 'Weather module $moduleId';
      case 3:
        return 'Mixer $moduleId';
      case 4:
        return 'Reservoir $moduleId';
      case 5:
        return 'Storage $moduleId';
      default:
        return 'Module $moduleId';
    }
  }
}

class TopologyRequest {
  const TopologyRequest({
    required this.reqId,
    required this.moduleId,
    required this.fc,
    required this.startReg,
    required this.regCount,
  });

  final int reqId;
  final int moduleId;
  final int fc;
  final int startReg;
  final int regCount;

  factory TopologyRequest.fromJson(Map<String, dynamic> json) {
    return TopologyRequest(
      reqId: _readInt(json, 'req_id'),
      moduleId: _readInt(json, 'module_id'),
      fc: _readInt(json, 'fc'),
      startReg: _readInt(json, 'start_reg'),
      regCount: _readInt(json, 'reg_count'),
    );
  }
}

class TopologyPoint {
  const TopologyPoint({
    required this.pointId,
    required this.moduleId,
    required this.reqId,
    required this.pointType,
    required this.scalePow10,
    required this.publishIndex,
    required this.qualityPolicy,
    required this.staleTimeoutS,
    required this.alarmLow,
    required this.alarmHigh,
    required this.semanticName,
    required this.label,
  });

  final int pointId;
  final int moduleId;
  final int reqId;
  final int pointType;
  final int scalePow10;
  final int publishIndex;
  final int qualityPolicy;
  final int staleTimeoutS;
  final int alarmLow;
  final int alarmHigh;
  final String? semanticName;
  final String? label;

  String get displayName =>
      label == null || label!.isEmpty
          ? (semanticName == null || semanticName!.isEmpty
                ? 'Point $pointId'
                : semanticName!)
          : label!;

  factory TopologyPoint.fromJson(Map<String, dynamic> json) {
    return TopologyPoint(
      pointId: _readInt(json, 'point_id'),
      moduleId: _readInt(json, 'module_id'),
      reqId: _readInt(json, 'req_id'),
      pointType: _readInt(json, 'point_type'),
      scalePow10: _readInt(json, 'scale_pow10'),
      publishIndex: _readInt(json, 'publish_index'),
      qualityPolicy: _readInt(json, 'quality_policy'),
      staleTimeoutS: _readInt(json, 'stale_timeout_s'),
      alarmLow: _readInt(json, 'alarm_low', defaultValue: 0),
      alarmHigh: _readInt(json, 'alarm_high', defaultValue: 0),
      semanticName: _readString(json, 'semantic_name'),
      label: _readString(json, 'label'),
    );
  }
}

class TopologyCommand {
  const TopologyCommand({
    required this.cmdId,
    required this.moduleId,
    required this.fc,
    required this.startReg,
    required this.maxRegCount,
    required this.payloadOffset,
    required this.timeoutMs,
    required this.ackPointId,
    required this.cmdKind,
    required this.semanticName,
    required this.uiGroup,
    required this.uiCapability,
  });

  final int cmdId;
  final int moduleId;
  final int fc;
  final int startReg;
  final int maxRegCount;
  final int payloadOffset;
  final int timeoutMs;
  final int ackPointId;
  final String cmdKind;
  final String? semanticName;
  final String? uiGroup;
  final String? uiCapability;

  factory TopologyCommand.fromJson(Map<String, dynamic> json) {
    final rawKind = json['cmd_kind'];
    var cmdKind = _normalizeCmdKind(rawKind);
    if (cmdKind == null) {
      final flags = _readInt(json, 'flags', defaultValue: 0);
      cmdKind = ((flags >> 14) & 0x3) == 1 ? 'schedule' : 'generic';
    }
    return TopologyCommand(
      cmdId: _readInt(json, 'cmd_id'),
      moduleId: _readInt(json, 'module_id'),
      fc: _readInt(json, 'fc'),
      startReg: _readInt(json, 'start_reg'),
      maxRegCount: _readInt(json, 'max_reg_count'),
      payloadOffset: _readInt(json, 'payload_offset'),
      timeoutMs: _readInt(json, 'timeout_ms'),
      ackPointId: _readInt(json, 'ack_point_id', defaultValue: 0),
      cmdKind: cmdKind,
      semanticName: _readString(json, 'semantic_name'),
      uiGroup: _readString(json, 'ui_group'),
      uiCapability: _readString(json, 'ui_capability'),
    );
  }
}

class TopologyPolicy {
  const TopologyPolicy({
    required this.moduleId,
    required this.onTimeout,
    required this.onCrcError,
    required this.onLinkLoss,
    required this.maxConsecutiveFail,
    required this.recoverGoodCycles,
    required this.safeProfileId,
  });

  final int moduleId;
  final int onTimeout;
  final int onCrcError;
  final int onLinkLoss;
  final int maxConsecutiveFail;
  final int recoverGoodCycles;
  final int safeProfileId;

  factory TopologyPolicy.fromJson(Map<String, dynamic> json) {
    return TopologyPolicy(
      moduleId: _readInt(json, 'module_id'),
      onTimeout: _readInt(json, 'on_timeout'),
      onCrcError: _readInt(json, 'on_crc_error'),
      onLinkLoss: _readInt(json, 'on_link_loss'),
      maxConsecutiveFail: _readInt(json, 'max_consecutive_fail'),
      recoverGoodCycles: _readInt(json, 'recover_good_cycles'),
      safeProfileId: _readInt(json, 'safe_profile_id'),
    );
  }
}

int _readInt(
  Map<String, dynamic> json,
  String key, {
  int? defaultValue,
}) {
  final value = json[key];
  if (value == null) {
    if (defaultValue != null) {
      return defaultValue;
    }
    throw FormatException('Missing integer field: $key');
  }
  if (value is int) {
    return value;
  }
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) {
      return parsed;
    }
  }
  throw FormatException('Invalid integer field: $key');
}

String? _readString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

List<Map<String, dynamic>> _readList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return const <Map<String, dynamic>>[];
  }
  if (value is! List) {
    throw FormatException('Invalid list field: $key');
  }
  return value
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList(growable: false);
}

String? _normalizeCmdKind(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value == 1 ? 'schedule' : 'generic';
  }
  final text = value.toString().trim().toLowerCase();
  if (text.isEmpty) {
    return null;
  }
  if (text == '1') {
    return 'schedule';
  }
  if (text == '0') {
    return 'generic';
  }
  return text;
}
