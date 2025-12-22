import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/irrigation_models.dart';
import '../../services/irrigation_repository.dart';
import 'irrigation_event.dart';
import 'irrigation_state.dart';

class IrrigationBloc extends Bloc<IrrigationEvent, IrrigationState> {
  final IrrigationRepository _repository;
  StreamSubscription? _machinesSubscription;

  IrrigationBloc({required IrrigationRepository repository})
    : _repository = repository,
      super(IrrigationInitial()) {
    on<LoadIrrigationData>(_onLoadData);
    on<StartMachineProgram>(_onStartProgram);
    on<StopMachineProgram>(_onStopProgram);
    on<EmergencyStopAll>(_onEmergencyStop);
    on<UpdateMachineSettings>(_onUpdateSettings);
    on<AddSchedule>(_onAddSchedule);
    on<UpdateSchedule>(_onUpdateSchedule);
    on<DeleteSchedule>(_onDeleteSchedule);
    on<StartBlock>(_onStartBlock);
    on<_IrrigationUpdated>(_onIrrigationUpdated);
  }

  void _onAddSchedule(AddSchedule event, Emitter<IrrigationState> emit) {
    _repository.addSchedule(event.machineId, event.schedule);
  }

  void _onUpdateSchedule(UpdateSchedule event, Emitter<IrrigationState> emit) {
    _repository.updateSchedule(event.machineId, event.schedule);
  }

  void _onDeleteSchedule(DeleteSchedule event, Emitter<IrrigationState> emit) {
    _repository.deleteSchedule(event.machineId, event.scheduleId);
  }

  void _onStartBlock(StartBlock event, Emitter<IrrigationState> emit) {
    _repository.startBlock(event.machineId, event.blockId);
  }

  void _onUpdateSettings(
    UpdateMachineSettings event,
    Emitter<IrrigationState> emit,
  ) {
    _repository.updateMachine(event.machine);
  }

  void _onLoadData(LoadIrrigationData event, Emitter<IrrigationState> emit) {
    emit(IrrigationLoading());
    _machinesSubscription?.cancel();
    _machinesSubscription = _repository.machinesStream.listen(
      (machines) => add(_IrrigationUpdated(machines)),
    );
  }

  void _onIrrigationUpdated(
    _IrrigationUpdated event,
    Emitter<IrrigationState> emit,
  ) {
    emit(IrrigationLoaded(event.machines));
  }

  void _onStartProgram(
    StartMachineProgram event,
    Emitter<IrrigationState> emit,
  ) {
    _repository.startProgram(event.machineId);
  }

  void _onStopProgram(StopMachineProgram event, Emitter<IrrigationState> emit) {
    _repository.stopProgram(event.machineId);
  }

  void _onEmergencyStop(EmergencyStopAll event, Emitter<IrrigationState> emit) {
    if (state is IrrigationLoaded) {
      final machines = (state as IrrigationLoaded).machines;
      for (var machine in machines) {
        _repository.stopProgram(machine.id);
      }
    }
  }

  @override
  Future<void> close() {
    _machinesSubscription?.cancel();
    return super.close();
  }
}

// Private internal event
class _IrrigationUpdated extends IrrigationEvent {
  final List<IrrigationMachine> machines;
  const _IrrigationUpdated(this.machines);
  @override
  List<Object> get props => [machines];
}
