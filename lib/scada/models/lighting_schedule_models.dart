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

  static LightingScheduleSlot disabled() => const LightingScheduleSlot(
    enabled: false,
    onHhmm: 0,
    offHhmm: 0,
  );
}

class LightingScheduleDraft {
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
        4,
        (_) => LightingScheduleSlot.disabled(),
      ),
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
      moduleId: moduleId,
      zoneId: zoneId,
      slaveId: slaveId,
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
