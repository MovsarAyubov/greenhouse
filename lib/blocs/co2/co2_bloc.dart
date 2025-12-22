import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../models/co2_schedule_item.dart';
import '../../services/climate_repository.dart';
import 'co2_event.dart';
import 'co2_state.dart';

class Co2Bloc extends Bloc<Co2Event, Co2State> {
  final ClimateRepository _repository;
  Timer? _timer;

  Co2Bloc({required ClimateRepository repository})
    : _repository = repository,
      super(const Co2State()) {
    on<LoadCo2Schedules>(_onLoadSchedules);
    on<AddCo2Schedule>(_onAddSchedule);
    on<UpdateCo2Schedule>(_onUpdateSchedule);
    on<DeleteCo2Schedule>(_onDeleteSchedule);
    on<Co2TimerTick>(_onTimerTick);

    // Start the timer
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => add(Co2TimerTick()),
    );
  }

  void _onLoadSchedules(LoadCo2Schedules event, Emitter<Co2State> emit) {
    // Initial dummy data for demonstration
    final defaultSchedules = [
      Co2ScheduleItem(
        id: const Uuid().v4(),
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 16, minute: 0),
        workDurationMinutes: 15,
        pauseDurationMinutes: 15,
      ),
      Co2ScheduleItem(
        id: const Uuid().v4(),
        startTime: const TimeOfDay(hour: 16, minute: 0),
        endTime: const TimeOfDay(hour: 20, minute: 0),
        workDurationMinutes: 10,
        pauseDurationMinutes: 20,
      ),
    ];
    emit(state.copyWith(schedules: defaultSchedules));
  }

  void _onAddSchedule(AddCo2Schedule event, Emitter<Co2State> emit) {
    final updatedSchedules = List<Co2ScheduleItem>.from(state.schedules)
      ..add(event.schedule);
    emit(state.copyWith(schedules: updatedSchedules));
  }

  void _onUpdateSchedule(UpdateCo2Schedule event, Emitter<Co2State> emit) {
    final updatedSchedules = state.schedules
        .map((s) => s.id == event.schedule.id ? event.schedule : s)
        .toList();
    emit(state.copyWith(schedules: updatedSchedules));
  }

  void _onDeleteSchedule(DeleteCo2Schedule event, Emitter<Co2State> emit) {
    final updatedSchedules = state.schedules
        .where((s) => s.id != event.id)
        .toList();
    emit(state.copyWith(schedules: updatedSchedules));
  }

  void _onTimerTick(Co2TimerTick event, Emitter<Co2State> emit) {
    final now = TimeOfDay.now();
    final currentMinutes = now.hour * 60 + now.minute;

    // Find active schedule
    Co2ScheduleItem? matchingSchedule;
    for (final schedule in state.schedules) {
      if (!schedule.isEnabled) continue;

      final start = schedule.startTime.hour * 60 + schedule.startTime.minute;
      final end = schedule.endTime.hour * 60 + schedule.endTime.minute;

      bool isWithinWindow;
      if (start < end) {
        isWithinWindow = currentMinutes >= start && currentMinutes < end;
      } else {
        // Midnight crossing
        isWithinWindow = currentMinutes >= start || currentMinutes < end;
      }

      if (isWithinWindow) {
        matchingSchedule = schedule;
        break;
      }
    }

    if (matchingSchedule == null) {
      if (state.status != Co2OperationStatus.idle) {
        emit(
          state.copyWithNullableSchedule(
            status: Co2OperationStatus.idle,
            clearActiveSchedule: true,
            remainingSeconds: 0,
          ),
        );
        _repository.setCo2(false);
      }
      return;
    }

    // If schedule changed or just started
    if (state.activeSchedule?.id != matchingSchedule.id) {
      emit(
        state.copyWith(
          activeSchedule: matchingSchedule,
          status: Co2OperationStatus.dosing,
          remainingSeconds: matchingSchedule.workDurationMinutes * 60,
        ),
      );
      _repository.setCo2(true);
      return;
    }

    // Logic for cycle
    if (state.remainingSeconds > 0) {
      emit(state.copyWith(remainingSeconds: state.remainingSeconds - 1));
    } else {
      // Switch state
      if (state.status == Co2OperationStatus.dosing) {
        emit(
          state.copyWith(
            status: Co2OperationStatus.pausing,
            remainingSeconds: matchingSchedule.pauseDurationMinutes * 60,
          ),
        );
        _repository.setCo2(false);
      } else if (state.status == Co2OperationStatus.pausing) {
        emit(
          state.copyWith(
            status: Co2OperationStatus.dosing,
            remainingSeconds: matchingSchedule.workDurationMinutes * 60,
          ),
        );
        _repository.setCo2(true);
      }
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
