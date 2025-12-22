import 'package:equatable/equatable.dart';
import '../../models/lighting_models.dart';

abstract class LightingEvent extends Equatable {
  const LightingEvent();

  @override
  List<Object?> get props => [];
}

class LoadLightingSchedules extends LightingEvent {}

class AddLightingSchedule extends LightingEvent {
  final LightingScheduleItem schedule;

  const AddLightingSchedule(this.schedule);

  @override
  List<Object?> get props => [schedule];
}

class UpdateLightingSchedule extends LightingEvent {
  final LightingScheduleItem schedule;

  const UpdateLightingSchedule(this.schedule);

  @override
  List<Object?> get props => [schedule];
}

class DeleteLightingSchedule extends LightingEvent {
  final String id;

  const DeleteLightingSchedule(this.id);

  @override
  List<Object?> get props => [id];
}

class ToggleBlockLight extends LightingEvent {
  final int blockId;

  const ToggleBlockLight(this.blockId);

  @override
  List<Object?> get props => [blockId];
}

class LightingTimerTick extends LightingEvent {}
