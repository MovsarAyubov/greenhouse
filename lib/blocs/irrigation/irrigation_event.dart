import 'package:equatable/equatable.dart';
import '../../models/irrigation_models.dart';

abstract class IrrigationEvent extends Equatable {
  const IrrigationEvent();

  @override
  List<Object> get props => [];
}

class LoadIrrigationData extends IrrigationEvent {}

class StartMachineProgram extends IrrigationEvent {
  final String machineId;
  const StartMachineProgram(this.machineId);
  @override
  List<Object> get props => [machineId];
}

class StopMachineProgram extends IrrigationEvent {
  final String machineId;
  const StopMachineProgram(this.machineId);
  @override
  List<Object> get props => [machineId];
}

class EmergencyStopAll extends IrrigationEvent {}

class UpdateMachineSettings extends IrrigationEvent {
  final IrrigationMachine machine;
  const UpdateMachineSettings(this.machine);
  @override
  List<Object> get props => [machine];
}

class AddSchedule extends IrrigationEvent {
  final String machineId;
  final IrrigationScheduleItem schedule;
  const AddSchedule(this.machineId, this.schedule);
  @override
  List<Object> get props => [machineId, schedule];
}

class UpdateSchedule extends IrrigationEvent {
  final String machineId;
  final IrrigationScheduleItem schedule;
  const UpdateSchedule(this.machineId, this.schedule);
  @override
  List<Object> get props => [machineId, schedule];
}

class DeleteSchedule extends IrrigationEvent {
  final String machineId;
  final String scheduleId;
  const DeleteSchedule(this.machineId, this.scheduleId);
  @override
  List<Object> get props => [machineId, scheduleId];
}

class StartBlock extends IrrigationEvent {
  final String machineId;
  final String blockId;
  const StartBlock(this.machineId, this.blockId);
  @override
  List<Object> get props => [machineId, blockId];
}
