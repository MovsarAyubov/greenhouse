enum LightingSchedulePhase {
  idle,
  pending,
  success,
  failed,
  timeout,
}

class LightingScheduleSlot {
  const LightingScheduleSlot({
    required this.enabled,
    required this.onHhmm,
    required this.offHhmm,
  });

  final bool enabled;
  final int onHhmm;
  final int offHhmm;

  LightingScheduleSlot copyWith({
    bool? enabled,
    int? onHhmm,
    int? offHhmm,
  }) {
    return LightingScheduleSlot(
      enabled: enabled ?? this.enabled,
      onHhmm: onHhmm ?? this.onHhmm,
      offHhmm: offHhmm ?? this.offHhmm,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'enabled': enabled,
      'on_hhmm': onHhmm,
      'off_hhmm': offHhmm,
    };
  }

  static LightingScheduleSlot fromJson(Object? value) {
    final map = _mapValue(value);
    return LightingScheduleSlot(
      enabled: _readBoolValue(map['enabled']) ?? false,
      onHhmm: _readIntValue(map['on_hhmm']) ?? 0,
      offHhmm: _readIntValue(map['off_hhmm']) ?? 0,
    );
  }

  static LightingScheduleSlot disabled() => const LightingScheduleSlot(
    enabled: false,
    onHhmm: 0,
    offHhmm: 0,
  );
}

class LightingScheduleDraft {
  static const int slotCount = 4;

  const LightingScheduleDraft({
    required this.moduleId,
    required this.zoneId,
    required this.slaveId,
    required this.slots,
    this.applyValue = 1,
    this.expectedActiveCtrlVersion = 0,
    this.strictVersion = false,
  });

  final int moduleId;
  final int zoneId;
  final int slaveId;
  final List<LightingScheduleSlot> slots;
  final int applyValue;
  final int expectedActiveCtrlVersion;
  final bool strictVersion;

  LightingScheduleDraft copyWith({
    int? moduleId,
    int? zoneId,
    int? slaveId,
    List<LightingScheduleSlot>? slots,
    int? applyValue,
    int? expectedActiveCtrlVersion,
    bool? strictVersion,
  }) {
    return LightingScheduleDraft(
      moduleId: moduleId ?? this.moduleId,
      zoneId: zoneId ?? this.zoneId,
      slaveId: slaveId ?? this.slaveId,
      slots: slots ?? this.slots,
      applyValue: applyValue ?? this.applyValue,
      expectedActiveCtrlVersion:
          expectedActiveCtrlVersion ?? this.expectedActiveCtrlVersion,
      strictVersion: strictVersion ?? this.strictVersion,
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
      slots: _normalizeSlots(slots),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'module_id': moduleId,
      'zone_id': zoneId,
      'slave_id': slaveId,
      'slots': slots.map((slot) => slot.toJson()).toList(growable: false),
      'apply_value': applyValue,
      'expected_active_ctrl_version': expectedActiveCtrlVersion,
      'strict_version': strictVersion,
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
    final rawSlots = map['slots'];
    final slots = rawSlots is List
        ? rawSlots.map(LightingScheduleSlot.fromJson)
        : const <LightingScheduleSlot>[];
    return LightingScheduleDraft(
      moduleId: moduleId,
      zoneId: zoneId,
      slaveId: slaveId,
      slots: _normalizeSlots(slots),
      applyValue: _readIntValue(map['apply_value']) ?? 1,
      expectedActiveCtrlVersion:
          _readIntValue(map['expected_active_ctrl_version']) ?? 0,
      strictVersion: _readBoolValue(map['strict_version']) ?? false,
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
      slots: List<LightingScheduleSlot>.generate(
        slotCount,
        (_) => LightingScheduleSlot.disabled(),
      ),
    );
  }

  static List<LightingScheduleSlot> _normalizeSlots(
    Iterable<LightingScheduleSlot> slots,
  ) {
    final normalized = slots.take(slotCount).toList(growable: true);
    while (normalized.length < slotCount) {
      normalized.add(LightingScheduleSlot.disabled());
    }
    return List<LightingScheduleSlot>.unmodifiable(normalized);
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
