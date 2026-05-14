enum WindowSetpointPhase { idle, pending, success, failed }

class WindowSetpointRegister {
  const WindowSetpointRegister._();

  static const int posATarget = 103;
  static const int posBTarget = 104;
  static const int ctrlMode = 171;
  static const int forceSafeCmd = 172;
  static const int tempSetpoint = 173;
  static const int safeMinPercent = 174;
  static const int windLimit = 175;
  static const int windStorm = 176;
  static const int windRecover = 177;
  static const int windowAAzimuthDeg = 178;
  static const int windSectorHalfWidthDeg = 179;
  static const int tempStepC = 180;
  static const int tempStepHystC = 181;
  static const int targetHystPercent = 182;
  static const int motionDeltaPercent = 183;
  static const int noMotionTimeoutMs = 184;
  static const int windowAFaultResetToken = 185;
  static const int windowBFaultResetToken = 186;
  static const int autoAlgoMode = 195;
  static const int humSetpoint = 196;
  static const int humStep = 197;
  static const int humStepHyst = 198;
  static const int coldCloseDelta = 199;
  static const int coldCloseHyst = 200;
  static const int windwardMinPercent = 201;
  static const int windwardMaxPercent = 202;
  static const int windwardSpeedThreshold = 203;
  static const int windwardReductionPercentPerMs = 204;
  static const int leewardMinPercent = 205;
  static const int leewardMaxPercent = 206;
  static const int leewardSpeedThreshold = 207;
  static const int leewardReductionPercentPerMs = 208;
  static const int windwardLagPercent = 209;
  static const int rainMode = 210;
  static const int rainWindwardPercent = 211;
  static const int weatherStalePolicy = 212;
  static const int tempStepTargetPercent = 219;
  static const int tempStepMaxIndex = 220;
  static const int humStepTargetPercent = 221;
  static const int humStepMaxIndex = 222;
  static const int weatherStaleTimeoutMs = 223;
  static const int weatherSourceAgeS = 224;
  static const int curtainCtrlMode = 243;
  static const int curtainManualTarget = 244;
  static const int curtainScheduleStartHhmm = 245;
  static const int curtainScheduleEndHhmm = 246;
  static const int curtainOutsideTarget = 247;
  static const int curtainMinPosition = 248;
  static const int curtainMaxPosition = 249;
  static const int curtainPositionHyst = 250;
  static const int curtainRadiationThreshold = 251;
  static const int curtainRadiationStepWm2 = 252;
  static const int curtainRadiationStepPercent = 253;
  static const int curtainRadiationHyst = 254;
  static const int curtainColdDelta = 255;
  static const int curtainColdHyst = 256;
  static const int curtainColdTarget = 257;
  static const int curtainHeatDelta = 258;
  static const int curtainHeatHyst = 259;
  static const int curtainHeatTarget = 260;
  static const int curtainHumLowThreshold = 261;
  static const int curtainHumLowHyst = 262;
  static const int curtainHumLowTarget = 263;
  static const int curtainHumHighThreshold = 264;
  static const int curtainHumHighHyst = 265;
  static const int curtainHumHighTarget = 266;
  static const int curtainFaultResetToken = 274;
  static const int airTempTarget = 275;
  static const int airHumTarget = 276;
}

class WindowSetpointProfile {
  const WindowSetpointProfile._();

  static const int manualTargetsZone1 = 5002;
  static const int manualTargetsZone2 = 5008;
  static const int baseZone1 = 5004;
  static const int baseZone2 = 5009;
  static const int automationZone1 = 5005;
  static const int automationZone2 = 5010;
  static const int rainWeatherZone1 = 5006;
  static const int rainWeatherZone2 = 5011;
  static const int stepTimeoutsZone1 = 5007;
  static const int stepTimeoutsZone2 = 5012;
  static const int curtainCoreZone1 = 5015;
  static const int curtainRadTempZone1 = 5016;
  static const int curtainHumZone1 = 5017;
  static const int curtainFaultResetZone1 = 5018;
  static const int greenhouseTargetsZone1 = 5019;
  static const int curtainCoreZone2 = 5020;
  static const int curtainRadTempZone2 = 5021;
  static const int curtainHumZone2 = 5022;
  static const int curtainFaultResetZone2 = 5023;
  static const int greenhouseTargetsZone2 = 5024;
}

class WindowSetpointCommandBlock {
  const WindowSetpointCommandBlock({
    required this.profileId,
    required this.registers,
    this.zone2ProfileId,
  });

  final int profileId;
  final int? zone2ProfileId;
  final List<int> registers;

  int profileIdFor(WindowSetpointDraft draft) {
    if (draft.zoneId == 2) {
      return zone2ProfileId ?? profileId;
    }
    return profileId;
  }

  List<int> payloadFor(WindowSetpointDraft draft) {
    return registers.map(draft.valueFor).toList(growable: false);
  }
}

const List<WindowSetpointCommandBlock> windowSetpointCommandBlocks =
    <WindowSetpointCommandBlock>[
      WindowSetpointCommandBlock(
        profileId: WindowSetpointProfile.manualTargetsZone1,
        zone2ProfileId: WindowSetpointProfile.manualTargetsZone2,
        registers: <int>[
          WindowSetpointRegister.posATarget,
          WindowSetpointRegister.posBTarget,
        ],
      ),
      WindowSetpointCommandBlock(
        profileId: WindowSetpointProfile.baseZone1,
        zone2ProfileId: WindowSetpointProfile.baseZone2,
        registers: <int>[
          WindowSetpointRegister.ctrlMode,
          WindowSetpointRegister.forceSafeCmd,
          WindowSetpointRegister.tempSetpoint,
          WindowSetpointRegister.safeMinPercent,
          WindowSetpointRegister.windLimit,
          WindowSetpointRegister.windStorm,
          WindowSetpointRegister.windRecover,
          WindowSetpointRegister.windowAAzimuthDeg,
          WindowSetpointRegister.windSectorHalfWidthDeg,
          WindowSetpointRegister.tempStepC,
          WindowSetpointRegister.tempStepHystC,
          WindowSetpointRegister.targetHystPercent,
          WindowSetpointRegister.motionDeltaPercent,
          WindowSetpointRegister.noMotionTimeoutMs,
          WindowSetpointRegister.windowAFaultResetToken,
          WindowSetpointRegister.windowBFaultResetToken,
        ],
      ),
      WindowSetpointCommandBlock(
        profileId: WindowSetpointProfile.automationZone1,
        zone2ProfileId: WindowSetpointProfile.automationZone2,
        registers: <int>[
          WindowSetpointRegister.autoAlgoMode,
          WindowSetpointRegister.humSetpoint,
          WindowSetpointRegister.humStep,
          WindowSetpointRegister.humStepHyst,
          WindowSetpointRegister.coldCloseDelta,
          WindowSetpointRegister.coldCloseHyst,
          WindowSetpointRegister.windwardMinPercent,
          WindowSetpointRegister.windwardMaxPercent,
          WindowSetpointRegister.windwardSpeedThreshold,
          WindowSetpointRegister.windwardReductionPercentPerMs,
          WindowSetpointRegister.leewardMinPercent,
          WindowSetpointRegister.leewardMaxPercent,
          WindowSetpointRegister.leewardSpeedThreshold,
          WindowSetpointRegister.leewardReductionPercentPerMs,
          WindowSetpointRegister.windwardLagPercent,
          WindowSetpointRegister.rainMode,
        ],
      ),
      WindowSetpointCommandBlock(
        profileId: WindowSetpointProfile.rainWeatherZone1,
        zone2ProfileId: WindowSetpointProfile.rainWeatherZone2,
        registers: <int>[
          WindowSetpointRegister.rainWindwardPercent,
          WindowSetpointRegister.weatherStalePolicy,
        ],
      ),
      WindowSetpointCommandBlock(
        profileId: WindowSetpointProfile.stepTimeoutsZone1,
        zone2ProfileId: WindowSetpointProfile.stepTimeoutsZone2,
        registers: <int>[
          WindowSetpointRegister.tempStepTargetPercent,
          WindowSetpointRegister.tempStepMaxIndex,
          WindowSetpointRegister.humStepTargetPercent,
          WindowSetpointRegister.humStepMaxIndex,
          WindowSetpointRegister.weatherStaleTimeoutMs,
          WindowSetpointRegister.weatherSourceAgeS,
        ],
      ),
      WindowSetpointCommandBlock(
        profileId: WindowSetpointProfile.curtainCoreZone1,
        zone2ProfileId: WindowSetpointProfile.curtainCoreZone2,
        registers: <int>[
          WindowSetpointRegister.curtainCtrlMode,
          WindowSetpointRegister.curtainManualTarget,
          WindowSetpointRegister.curtainScheduleStartHhmm,
          WindowSetpointRegister.curtainScheduleEndHhmm,
          WindowSetpointRegister.curtainOutsideTarget,
          WindowSetpointRegister.curtainMinPosition,
          WindowSetpointRegister.curtainMaxPosition,
          WindowSetpointRegister.curtainPositionHyst,
        ],
      ),
      WindowSetpointCommandBlock(
        profileId: WindowSetpointProfile.curtainRadTempZone1,
        zone2ProfileId: WindowSetpointProfile.curtainRadTempZone2,
        registers: <int>[
          WindowSetpointRegister.curtainRadiationThreshold,
          WindowSetpointRegister.curtainRadiationStepWm2,
          WindowSetpointRegister.curtainRadiationStepPercent,
          WindowSetpointRegister.curtainRadiationHyst,
          WindowSetpointRegister.curtainColdDelta,
          WindowSetpointRegister.curtainColdHyst,
          WindowSetpointRegister.curtainColdTarget,
          WindowSetpointRegister.curtainHeatDelta,
          WindowSetpointRegister.curtainHeatHyst,
          WindowSetpointRegister.curtainHeatTarget,
        ],
      ),
      WindowSetpointCommandBlock(
        profileId: WindowSetpointProfile.curtainHumZone1,
        zone2ProfileId: WindowSetpointProfile.curtainHumZone2,
        registers: <int>[
          WindowSetpointRegister.curtainHumLowThreshold,
          WindowSetpointRegister.curtainHumLowHyst,
          WindowSetpointRegister.curtainHumLowTarget,
          WindowSetpointRegister.curtainHumHighThreshold,
          WindowSetpointRegister.curtainHumHighHyst,
          WindowSetpointRegister.curtainHumHighTarget,
        ],
      ),
      WindowSetpointCommandBlock(
        profileId: WindowSetpointProfile.curtainFaultResetZone1,
        zone2ProfileId: WindowSetpointProfile.curtainFaultResetZone2,
        registers: <int>[WindowSetpointRegister.curtainFaultResetToken],
      ),
      WindowSetpointCommandBlock(
        profileId: WindowSetpointProfile.greenhouseTargetsZone1,
        zone2ProfileId: WindowSetpointProfile.greenhouseTargetsZone2,
        registers: <int>[
          WindowSetpointRegister.airTempTarget,
          WindowSetpointRegister.airHumTarget,
        ],
      ),
    ];

List<int> get windowSetpointRegisters => windowSetpointCommandBlocks
    .expand((block) => block.registers)
    .toSet()
    .toList(growable: false);

const List<int> visibleWindowSetpointRegisters = <int>[
  WindowSetpointRegister.posATarget,
  WindowSetpointRegister.posBTarget,
  WindowSetpointRegister.ctrlMode,
  WindowSetpointRegister.forceSafeCmd,
  WindowSetpointRegister.tempSetpoint,
  WindowSetpointRegister.safeMinPercent,
  WindowSetpointRegister.tempStepC,
  WindowSetpointRegister.tempStepHystC,
  WindowSetpointRegister.targetHystPercent,
  WindowSetpointRegister.motionDeltaPercent,
  WindowSetpointRegister.noMotionTimeoutMs,
  WindowSetpointRegister.windStorm,
  WindowSetpointRegister.windRecover,
  WindowSetpointRegister.windowAAzimuthDeg,
  WindowSetpointRegister.windSectorHalfWidthDeg,
  WindowSetpointRegister.autoAlgoMode,
  WindowSetpointRegister.humSetpoint,
  WindowSetpointRegister.humStep,
  WindowSetpointRegister.humStepHyst,
  WindowSetpointRegister.coldCloseDelta,
  WindowSetpointRegister.coldCloseHyst,
  WindowSetpointRegister.windwardMinPercent,
  WindowSetpointRegister.windwardMaxPercent,
  WindowSetpointRegister.windwardSpeedThreshold,
  WindowSetpointRegister.windwardReductionPercentPerMs,
  WindowSetpointRegister.leewardMinPercent,
  WindowSetpointRegister.leewardMaxPercent,
  WindowSetpointRegister.leewardSpeedThreshold,
  WindowSetpointRegister.leewardReductionPercentPerMs,
  WindowSetpointRegister.windwardLagPercent,
  WindowSetpointRegister.rainMode,
  WindowSetpointRegister.rainWindwardPercent,
  WindowSetpointRegister.weatherStalePolicy,
  WindowSetpointRegister.tempStepTargetPercent,
  WindowSetpointRegister.humStepTargetPercent,
  WindowSetpointRegister.weatherStaleTimeoutMs,
  WindowSetpointRegister.weatherSourceAgeS,
  WindowSetpointRegister.curtainCtrlMode,
  WindowSetpointRegister.curtainManualTarget,
  WindowSetpointRegister.curtainScheduleStartHhmm,
  WindowSetpointRegister.curtainScheduleEndHhmm,
  WindowSetpointRegister.curtainOutsideTarget,
  WindowSetpointRegister.curtainMinPosition,
  WindowSetpointRegister.curtainMaxPosition,
  WindowSetpointRegister.curtainPositionHyst,
  WindowSetpointRegister.curtainRadiationThreshold,
  WindowSetpointRegister.curtainRadiationStepWm2,
  WindowSetpointRegister.curtainRadiationStepPercent,
  WindowSetpointRegister.curtainRadiationHyst,
  WindowSetpointRegister.curtainColdDelta,
  WindowSetpointRegister.curtainColdHyst,
  WindowSetpointRegister.curtainColdTarget,
  WindowSetpointRegister.curtainHeatDelta,
  WindowSetpointRegister.curtainHeatHyst,
  WindowSetpointRegister.curtainHeatTarget,
  WindowSetpointRegister.curtainHumLowThreshold,
  WindowSetpointRegister.curtainHumLowHyst,
  WindowSetpointRegister.curtainHumLowTarget,
  WindowSetpointRegister.curtainHumHighThreshold,
  WindowSetpointRegister.curtainHumHighHyst,
  WindowSetpointRegister.curtainHumHighTarget,
  WindowSetpointRegister.curtainFaultResetToken,
  WindowSetpointRegister.airTempTarget,
  WindowSetpointRegister.airHumTarget,
];

class WindowSetpointDraft {
  const WindowSetpointDraft({
    required this.moduleId,
    required this.zoneId,
    required this.slaveId,
    required this.valuesByRegister,
  });

  final int moduleId;
  final int zoneId;
  final int slaveId;
  final Map<int, int> valuesByRegister;

  int valueFor(int register) => valuesByRegister[register] ?? 0;

  WindowSetpointDraft copyWithValue(int register, int value) {
    return WindowSetpointDraft(
      moduleId: moduleId,
      zoneId: zoneId,
      slaveId: slaveId,
      valuesByRegister: <int, int>{
        ...valuesByRegister,
        register: value & 0xFFFF,
      },
    );
  }

  WindowSetpointDraft copyWithValues(Map<int, int> values) {
    return WindowSetpointDraft(
      moduleId: moduleId,
      zoneId: zoneId,
      slaveId: slaveId,
      valuesByRegister: <int, int>{...valuesByRegister, ...values},
    );
  }

  WindowSetpointDraft rebind({
    required int moduleId,
    required int zoneId,
    required int slaveId,
  }) {
    return WindowSetpointDraft(
      moduleId: moduleId,
      zoneId: zoneId,
      slaveId: slaveId,
      valuesByRegister: _normalizedValues(valuesByRegister),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'module_id': moduleId,
      'zone_id': zoneId,
      'slave_id': slaveId,
      'values': <String, int>{
        for (final entry in _normalizedValues(valuesByRegister).entries)
          entry.key.toString(): entry.value,
      },
    };
  }

  static WindowSetpointDraft? fromJson(Object? value) {
    final map = _mapValue(value);
    final moduleId = _readIntValue(map['module_id']);
    final zoneId = _readIntValue(map['zone_id']);
    final slaveId = _readIntValue(map['slave_id']);
    if (moduleId == null || zoneId == null || slaveId == null) {
      return null;
    }
    final valuesMap = _mapValue(map['values']);
    final values = <int, int>{};
    for (final entry in valuesMap.entries) {
      final register = int.tryParse(entry.key);
      final rawValue = _readIntValue(entry.value);
      if (register == null || rawValue == null) {
        continue;
      }
      values[register] = rawValue;
    }
    _dropLegacyReactionDelay(values);
    return WindowSetpointDraft(
      moduleId: moduleId,
      zoneId: zoneId,
      slaveId: slaveId,
      valuesByRegister: _normalizedValues(values),
    );
  }

  static WindowSetpointDraft initial({
    required int moduleId,
    required int zoneId,
    required int slaveId,
  }) {
    return WindowSetpointDraft(
      moduleId: moduleId,
      zoneId: zoneId,
      slaveId: slaveId,
      valuesByRegister: _normalizedValues(const <int, int>{}),
    );
  }

  static Map<int, int> _normalizedValues(Map<int, int> raw) {
    return <int, int>{
      for (final register in windowSetpointRegisters)
        register: (raw[register] ?? _defaultValue(register)) & 0xFFFF,
    };
  }

  static int _defaultValue(int register) {
    switch (register) {
      case WindowSetpointRegister.ctrlMode:
      case WindowSetpointRegister.autoAlgoMode:
      case WindowSetpointRegister.rainMode:
      case WindowSetpointRegister.weatherStalePolicy:
        return 0;
      case WindowSetpointRegister.tempSetpoint:
      case WindowSetpointRegister.airTempTarget:
        return 250;
      case WindowSetpointRegister.humSetpoint:
      case WindowSetpointRegister.airHumTarget:
        return 700;
      case WindowSetpointRegister.weatherStaleTimeoutMs:
        return 60000;
      case WindowSetpointRegister.weatherSourceAgeS:
        return 60;
      default:
        return 0;
    }
  }
}

void _dropLegacyReactionDelay(Map<int, int> values) {
  if (!values.containsKey(WindowSetpointRegister.curtainCtrlMode)) {
    return;
  }
  final hasCurtainState = values.keys.any((register) {
    return register >= WindowSetpointRegister.curtainManualTarget &&
        register <= WindowSetpointRegister.curtainFaultResetToken;
  });
  if (hasCurtainState) {
    return;
  }
  values.remove(WindowSetpointRegister.curtainCtrlMode);
}

class WindowSetpointStatus {
  const WindowSetpointStatus({
    required this.moduleId,
    required this.zoneId,
    required this.slaveId,
    required this.phase,
    required this.draft,
    this.lastAttemptAt,
    this.message,
  });

  final int moduleId;
  final int zoneId;
  final int slaveId;
  final WindowSetpointPhase phase;
  final WindowSetpointDraft draft;
  final DateTime? lastAttemptAt;
  final String? message;

  WindowSetpointStatus copyWith({
    int? moduleId,
    int? zoneId,
    int? slaveId,
    WindowSetpointPhase? phase,
    WindowSetpointDraft? draft,
    DateTime? lastAttemptAt,
    String? message,
    bool clearMessage = false,
  }) {
    return WindowSetpointStatus(
      moduleId: moduleId ?? this.moduleId,
      zoneId: zoneId ?? this.zoneId,
      slaveId: slaveId ?? this.slaveId,
      phase: phase ?? this.phase,
      draft: draft ?? this.draft,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  static WindowSetpointStatus initial({
    required int moduleId,
    required int zoneId,
    required int slaveId,
  }) {
    return WindowSetpointStatus(
      moduleId: moduleId,
      zoneId: zoneId,
      slaveId: slaveId,
      phase: WindowSetpointPhase.idle,
      draft: WindowSetpointDraft.initial(
        moduleId: moduleId,
        zoneId: zoneId,
        slaveId: slaveId,
      ),
    );
  }
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return <String, dynamic>{};
}

int? _readIntValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}
