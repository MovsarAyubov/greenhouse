import '../models/lighting_schedule_models.dart';
import '../models/topology_models.dart';
import 'topology_resolver.dart';

class GenericCommandRequest {
  const GenericCommandRequest({
    required this.targetSlaveId,
    required this.targetModuleId,
    required this.cmdProfileId,
    required this.payload,
    required this.timeoutMs,
  });

  final int targetSlaveId;
  final int targetModuleId;
  final int cmdProfileId;
  final List<int> payload;
  final int timeoutMs;
}

class CommandBuilder {
  const CommandBuilder();

  GenericCommandRequest buildScheduleCommand({
    required TopologyModule module,
    required ScheduleCommandContract contract,
    required LightingScheduleDraft draft,
  }) {
    if (draft.slots.length != 4) {
      throw StateError('schedule must contain 4 slots');
    }
    final payload = <int>[];
    for (var i = 0; i < draft.slots.length; i++) {
      final slot = draft.slots[i];
      _validateHhmm(slot.onHhmm, 'SCH$i ON_HHMM');
      _validateHhmm(slot.offHhmm, 'SCH$i OFF_HHMM');
      if (slot.enabled && slot.onHhmm == slot.offHhmm) {
        throw StateError('SCH$i invalid: EN=1 and ON_HHMM == OFF_HHMM');
      }
      payload.add(slot.enabled ? 1 : 0);
      payload.add(slot.enabled ? slot.onHhmm & 0xFFFF : 0);
      payload.add(slot.enabled ? slot.offHhmm & 0xFFFF : 0);
    }
    final expectedVersion = draft.strictVersion
        ? draft.expectedActiveCtrlVersion
        : 0;
    payload.add(draft.applyValue & 0xFFFF);
    payload.add((expectedVersion >> 16) & 0xFFFF);
    payload.add(expectedVersion & 0xFFFF);
    payload.add(1);
    return GenericCommandRequest(
      targetSlaveId: module.slaveId,
      targetModuleId: module.moduleId,
      cmdProfileId: contract.primaryStep.cmdId,
      payload: payload,
      timeoutMs: contract.primaryStep.timeoutMs,
    );
  }

  void _validateHhmm(int value, String field) {
    if (value < 0 || value > 2359) {
      throw StateError('$field=$value is out of range');
    }
    final hh = value ~/ 100;
    final mm = value % 100;
    if (hh > 23 || mm > 59) {
      throw StateError('$field=$value is out of range');
    }
  }
}
