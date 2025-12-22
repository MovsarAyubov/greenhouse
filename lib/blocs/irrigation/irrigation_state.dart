import 'package:equatable/equatable.dart';
import '../../models/irrigation_models.dart';

abstract class IrrigationState extends Equatable {
  const IrrigationState();

  @override
  List<Object> get props => [];
}

class IrrigationInitial extends IrrigationState {}

class IrrigationLoading extends IrrigationState {}

class IrrigationLoaded extends IrrigationState {
  final List<IrrigationMachine> machines;

  const IrrigationLoaded(this.machines);

  @override
  List<Object> get props => [machines];
}

class IrrigationError extends IrrigationState {
  final String message;

  const IrrigationError(this.message);

  @override
  List<Object> get props => [message];
}
