import 'package:equatable/equatable.dart';
import '../../models/co2_schedule_item.dart';
import 'co2_event.dart'; // For Co2CycleStatus enum if I put it there, or I can move it here or separate file.
// Actually I put Co2CycleStatus in co2_event.dart, let's move it to state or keep it consistent.
// I'll redefine it here or import it. Let's import it if possible, but usually enums are better in state or separate.
// I'll put the enum in state file for clarity this time or just use the one from event if I exported it?
// Wait, I defined it in event file. Let's move it to a separate file or just redefine/move to state.
// To avoid circular deps or confusion, I will put the enum in the state file and remove from event file in next edit if needed,
// or just put it here.

enum Co2OperationStatus { idle, dosing, pausing }

class Co2State extends Equatable {
  final List<Co2ScheduleItem> schedules;
  final Co2ScheduleItem? activeSchedule;
  final Co2OperationStatus status;
  final int
  remainingSeconds; // Time remaining in current status (dosing/pausing)

  const Co2State({
    this.schedules = const [],
    this.activeSchedule,
    this.status = Co2OperationStatus.idle,
    this.remainingSeconds = 0,
  });

  Co2State copyWith({
    List<Co2ScheduleItem>? schedules,
    Co2ScheduleItem? activeSchedule,
    Co2OperationStatus? status,
    int? remainingSeconds,
  }) {
    return Co2State(
      schedules: schedules ?? this.schedules,
      activeSchedule:
          activeSchedule ??
          this.activeSchedule, // Pass null to clear? No, usually copyWith ignores null.
      // To allow clearing, we might need a specific flag or nullable wrapper, but for now let's assume we just replace.
      // Actually, if I want to clear activeSchedule, I might need a better copyWith.
      // For simplicity, let's assume if activeSchedule is passed as null it is ignored,
      // but we might need a way to set it to null.
      // Let's use a specific logic: if status is idle, activeSchedule is likely null or irrelevant.
      status: status ?? this.status,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
    );
  }

  // Helper to allow setting activeSchedule to null
  Co2State copyWithNullableSchedule({
    List<Co2ScheduleItem>? schedules,
    Co2ScheduleItem? activeSchedule,
    bool clearActiveSchedule = false,
    Co2OperationStatus? status,
    int? remainingSeconds,
  }) {
    return Co2State(
      schedules: schedules ?? this.schedules,
      activeSchedule: clearActiveSchedule
          ? null
          : (activeSchedule ?? this.activeSchedule),
      status: status ?? this.status,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
    );
  }

  @override
  List<Object?> get props => [
    schedules,
    activeSchedule,
    status,
    remainingSeconds,
  ];
}
