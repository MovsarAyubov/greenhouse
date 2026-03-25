enum LightingSchedulePhase {
  idle,
  pending,
  success,
  failed,
  timeout,
}

class LightingRelayDraft {
  const LightingRelayDraft({
    required this.enabled,
    required this.onHhmm,
    required this.offHhmm,
    required this.thresholdWm2,
    required this.dliLimit,
  });

  final bool enabled;
  final int onHhmm;
  final int offHhmm;
  final int thresholdWm2;
  final int dliLimit;

  List<int> get payloadWords => <int>[
    enabled ? 1 : 0,
    onHhmm & 0xFFFF,
    offHhmm & 0xFFFF,
    thresholdWm2 & 0xFFFF,
    0,
    dliLimit & 0xFFFF,
  ];

  LightingRelayDraft copyWith({
    bool? enabled,
    int? onHhmm,
    int? offHhmm,
    int? thresholdWm2,
    int? dliLimit,
  }) {
    return LightingRelayDraft(
      enabled: enabled ?? this.enabled,
      onHhmm: onHhmm ?? this.onHhmm,
      offHhmm: offHhmm ?? this.offHhmm,
      thresholdWm2: thresholdWm2 ?? this.thresholdWm2,
      dliLimit: dliLimit ?? this.dliLimit,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'enabled': enabled,
      'on_hhmm': onHhmm,
      'off_hhmm': offHhmm,
      'threshold_wm2': thresholdWm2,
      'dli_limit': dliLimit,
    };
  }

  static LightingRelayDraft? fromJson(Object? value) {
    final map = _mapValue(value);
    if (map.isEmpty) {
      return null;
    }
    return LightingRelayDraft(
      enabled: _readBoolValue(map['enabled']) ?? false,
      onHhmm: _readIntValue(map['on_hhmm']) ?? 0,
      offHhmm: _readIntValue(map['off_hhmm']) ?? 0,
      thresholdWm2:
          _readIntValue(map['threshold_wm2']) ??
          _readIntValue(map['stage_1']) ??
          _readIntValue(map['threshold_1']) ??
          0,
      dliLimit: _readIntValue(map['dli_limit']) ?? 0,
    );
  }

  static const LightingRelayDraft disabled = LightingRelayDraft(
    enabled: false,
    onHhmm: 0,
    offHhmm: 0,
    thresholdWm2: 0,
    dliLimit: 0,
  );
}

class LightingScheduleDraft {
  const LightingScheduleDraft({
    required this.moduleId,
    required this.zoneId,
    required this.slaveId,
    required this.relay1,
    required this.relay2,
    required this.hysteresisSec,
  });

  final int moduleId;
  final int zoneId;
  final int slaveId;
  final LightingRelayDraft relay1;
  final LightingRelayDraft relay2;
  final int hysteresisSec;

  List<int> get payloadWords => <int>[
    ...relay1.payloadWords,
    ...relay2.payloadWords,
    hysteresisSec & 0xFFFF,
  ];

  LightingScheduleDraft copyWith({
    int? moduleId,
    int? zoneId,
    int? slaveId,
    LightingRelayDraft? relay1,
    LightingRelayDraft? relay2,
    int? hysteresisSec,
  }) {
    return LightingScheduleDraft(
      moduleId: moduleId ?? this.moduleId,
      zoneId: zoneId ?? this.zoneId,
      slaveId: slaveId ?? this.slaveId,
      relay1: relay1 ?? this.relay1,
      relay2: relay2 ?? this.relay2,
      hysteresisSec: hysteresisSec ?? this.hysteresisSec,
    );
  }

  LightingScheduleDraft rebind({
    required int moduleId,
    required int zoneId,
    required int slaveId,
  }) {
    return copyWith(
      moduleId: moduleId,
      zoneId: zoneId,
      slaveId: slaveId,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'module_id': moduleId,
      'zone_id': zoneId,
      'slave_id': slaveId,
      'relay_1': relay1.toJson(),
      'relay_2': relay2.toJson(),
      'light_hyst_sec': hysteresisSec,
    };
  }

  static LightingScheduleDraft? fromJson(Object? value) {
    final map = _mapValue(value);
    final moduleId = _readIntValue(map['module_id']);
    final zoneId = _readIntValue(map['zone_id']);
    final slaveId = _readIntValue(map['slave_id']);
    if (moduleId == null || zoneId == null || slaveId == null) {
      return null;
    }
    final legacyTiming = _legacyTimingFromJson(map['slots']);
    final legacyRelay1 = LightingRelayDraft(
      enabled: _readBoolValue(map['schedule_enabled']) ?? legacyTiming.enabled,
      onHhmm: _readIntValue(map['on_hhmm']) ?? legacyTiming.onHhmm,
      offHhmm: _readIntValue(map['off_hhmm']) ?? legacyTiming.offHhmm,
      thresholdWm2: _readIntValue(map['threshold_1']) ?? 0,
      dliLimit: _readIntValue(map['dli_limit']) ?? 0,
    );
    return LightingScheduleDraft(
      moduleId: moduleId,
      zoneId: zoneId,
      slaveId: slaveId,
      relay1: LightingRelayDraft.fromJson(map['relay_1']) ?? legacyRelay1,
      relay2:
          LightingRelayDraft.fromJson(map['relay_2']) ??
          LightingRelayDraft.disabled,
      hysteresisSec:
          _readIntValue(map['light_hyst_sec']) ??
          _readIntValue(map['hysteresis']) ??
          0,
    );
  }

  static LightingScheduleDraft initial({
    required int moduleId,
    required int zoneId,
    required int slaveId,
  }) {
    return LightingScheduleDraft(
      moduleId: moduleId,
      zoneId: zoneId,
      slaveId: slaveId,
      relay1: LightingRelayDraft.disabled,
      relay2: LightingRelayDraft.disabled,
      hysteresisSec: 0,
    );
  }
}

class LightingScheduleStatus {
  const LightingScheduleStatus({
    required this.moduleId,
    required this.zoneId,
    required this.slaveId,
    required this.phase,
    required this.draft,
    required this.trigger,
    required this.lastAppliedTrigger,
    required this.lastResult,
    required this.lastIoErr,
    this.lastAttemptAt,
    this.message,
  });

  final int moduleId;
  final int zoneId;
  final int slaveId;
  final LightingSchedulePhase phase;
  final LightingScheduleDraft draft;
  final int trigger;
  final int lastAppliedTrigger;
  final int lastResult;
  final int lastIoErr;
  final DateTime? lastAttemptAt;
  final String? message;

  LightingScheduleStatus copyWith({
    int? moduleId,
    int? zoneId,
    int? slaveId,
    LightingSchedulePhase? phase,
    LightingScheduleDraft? draft,
    int? trigger,
    int? lastAppliedTrigger,
    int? lastResult,
    int? lastIoErr,
    DateTime? lastAttemptAt,
    String? message,
    bool clearMessage = false,
  }) {
    return LightingScheduleStatus(
      moduleId: moduleId ?? this.moduleId,
      zoneId: zoneId ?? this.zoneId,
      slaveId: slaveId ?? this.slaveId,
      phase: phase ?? this.phase,
      draft: draft ?? this.draft,
      trigger: trigger ?? this.trigger,
      lastAppliedTrigger: lastAppliedTrigger ?? this.lastAppliedTrigger,
      lastResult: lastResult ?? this.lastResult,
      lastIoErr: lastIoErr ?? this.lastIoErr,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  static LightingScheduleStatus initial({
    required int moduleId,
    required int zoneId,
    required int slaveId,
  }) {
    return LightingScheduleStatus(
      moduleId: moduleId,
      zoneId: zoneId,
      slaveId: slaveId,
      phase: LightingSchedulePhase.idle,
      draft: LightingScheduleDraft.initial(
        moduleId: moduleId,
        zoneId: zoneId,
        slaveId: slaveId,
      ),
      trigger: 0,
      lastAppliedTrigger: 0,
      lastResult: 0,
      lastIoErr: 0,
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

bool? _readBoolValue(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is int) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
  }
  return null;
}

_LegacyLightingTiming _legacyTimingFromJson(Object? value) {
  if (value is! List) {
    return const _LegacyLightingTiming(enabled: false, onHhmm: 0, offHhmm: 0);
  }
  for (final item in value) {
    final map = _mapValue(item);
    final enabled = _readBoolValue(map['enabled']) ?? false;
    if (!enabled) {
      continue;
    }
    return _LegacyLightingTiming(
      enabled: true,
      onHhmm: _readIntValue(map['on_hhmm']) ?? 0,
      offHhmm: _readIntValue(map['off_hhmm']) ?? 0,
    );
  }
  return const _LegacyLightingTiming(enabled: false, onHhmm: 0, offHhmm: 0);
}

class _LegacyLightingTiming {
  const _LegacyLightingTiming({
    required this.enabled,
    required this.onHhmm,
    required this.offHhmm,
  });

  final bool enabled;
  final int onHhmm;
  final int offHhmm;
}
