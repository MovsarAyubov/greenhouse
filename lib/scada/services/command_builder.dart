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
    _validateRelay(draft.relay1, relayNumber: 1);
    _validateRelay(draft.relay2, relayNumber: 2);
    _validateUint16(draft.hysteresisSec, 'LIGHT_HYST_SEC');
    final payload = draft.payloadWords;
    if (payload.length != 13) {
      throw StateError('LIGHT payload must be 13 words, got ${payload.length}');
    }
    return GenericCommandRequest(
      targetSlaveId: module.slaveId,
      targetModuleId: module.moduleId,
      cmdProfileId: contract.cmdProfileId,
      payload: payload,
      timeoutMs: contract.timeoutMs,
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

  void _validateUint16(int value, String field) {
    if (value < 0 || value > 0xFFFF) {
      throw StateError('$field=$value is out of range');
    }
  }

  void _validateRelay(LightingRelayDraft relay, {required int relayNumber}) {
    _validateHhmm(relay.onHhmm, 'LIGHT_RELAY_${relayNumber}_ON_HHMM');
    _validateHhmm(relay.offHhmm, 'LIGHT_RELAY_${relayNumber}_OFF_HHMM');
    _validateUint16(
      relay.thresholdWm2,
      'LIGHT_RELAY_${relayNumber}_THRESHOLD_WM2',
    );
    _validateUint16(relay.dliLimit, 'LIGHT_RELAY_${relayNumber}_DLI_LIMIT');
  }
}
