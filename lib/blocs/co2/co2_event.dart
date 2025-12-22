import 'package:equatable/equatable.dart';
import '../../models/co2_schedule_item.dart';

enum Co2CycleStatus { idle, dosing, pausing }

abstract class Co2Event extends Equatable {
  const Co2Event();

  @override
  List<Object?> get props => [];
}

class LoadCo2Schedules extends Co2Event {}

class AddCo2Schedule extends Co2Event {
  final Co2ScheduleItem schedule;
  const AddCo2Schedule(this.schedule);
  @override
  List<Object?> get props => [schedule];
}

class UpdateCo2Schedule extends Co2Event {
  final Co2ScheduleItem schedule;
  const UpdateCo2Schedule(this.schedule);
  @override
  List<Object?> get props => [schedule];
}

class DeleteCo2Schedule extends Co2Event {
  final String id;
  const DeleteCo2Schedule(this.id);
  @override
  List<Object?> get props => [id];
}

class Co2TimerTick extends Co2Event {}
