import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:greenhouse/models/lighting_models.dart';
import 'package:uuid/uuid.dart';
import '../../services/climate_repository.dart';
import 'lighting_event.dart';
import 'lighting_state.dart';

class LightingBloc extends Bloc<LightingEvent, LightingState> {
  final ClimateRepository _repository;
  Timer? _timer;

  LightingBloc({required ClimateRepository repository})
    : _repository = repository,
      super(const LightingState()) {
    on<LoadLightingSchedules>(_onLoadSchedules);
    on<AddLightingSchedule>(_onAddSchedule);
    on<UpdateLightingSchedule>(_onUpdateSchedule);
    on<DeleteLightingSchedule>(_onDeleteSchedule);
    on<ToggleBlockLight>(_onToggleBlockLight);
    on<LightingTimerTick>(_onTimerTick);

    // Start timer
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => add(LightingTimerTick()),
    );
  }

  void _onToggleBlockLight(
    ToggleBlockLight event,
    Emitter<LightingState> emit,
  ) {
    final newStatus = Map<int, bool>.from(state.blockStatus);
    final current = newStatus[event.blockId] ?? false;
    final newValue = !current;
    newStatus[event.blockId] = newValue;

    // Send command to hardware
    // Note: This is a simplification. Ideally we'd have setBlockLight(id, val)
    // For now, if ANY block is on, we turn the main light on (or we can map blocks to coils later)
    // Let's assume setLight controls the main contactor for now.
    _repository.setLight(newValue);

    emit(state.copyWith(blockStatus: newStatus));
  }

  void _onLoadSchedules(
    LoadLightingSchedules event,
    Emitter<LightingState> emit,
  ) {
    // Dummy data
    final defaultSchedules = [
      LightingScheduleItem(
        id: const Uuid().v4(),
        startTime: const TimeOfDay(hour: 8, minute: 0),
        endTime: const TimeOfDay(hour: 20, minute: 0),
      ),
    ];
    emit(state.copyWith(schedules: defaultSchedules));
  }

  void _onAddSchedule(AddLightingSchedule event, Emitter<LightingState> emit) {
    final updated = List<LightingScheduleItem>.from(state.schedules)
      ..add(event.schedule);
    emit(state.copyWith(schedules: updated));
  }

  void _onUpdateSchedule(
    UpdateLightingSchedule event,
    Emitter<LightingState> emit,
  ) {
    final updated = state.schedules
        .map((s) => s.id == event.schedule.id ? event.schedule : s)
        .toList();
    emit(state.copyWith(schedules: updated));
  }

  void _onDeleteSchedule(
    DeleteLightingSchedule event,
    Emitter<LightingState> emit,
  ) {
    final updated = state.schedules.where((s) => s.id != event.id).toList();
    emit(state.copyWith(schedules: updated));
  }

  void _onTimerTick(LightingTimerTick event, Emitter<LightingState> emit) {
    final now = TimeOfDay.now();
    final currentMinutes = now.hour * 60 + now.minute;

    LightingScheduleItem? matchingSchedule;

    for (final schedule in state.schedules) {
      if (!schedule.isEnabled) continue;

      final start = schedule.startTime.hour * 60 + schedule.startTime.minute;
      final end = schedule.endTime.hour * 60 + schedule.endTime.minute;

      bool isWithinWindow;
      if (start < end) {
        // Normal window (e.g. 08:00 - 20:00)
        isWithinWindow = currentMinutes >= start && currentMinutes < end;
      } else {
        // Midnight crossing (e.g. 22:00 - 06:00)
        isWithinWindow = currentMinutes >= start || currentMinutes < end;
      }

      if (isWithinWindow) {
        matchingSchedule = schedule;
        break;
      }
    }

    if (matchingSchedule != null) {
      if (state.activeSchedule?.id != matchingSchedule.id ||
          state.status != LightingStatus.on) {
        emit(
          state.copyWith(
            status: LightingStatus.on,
            activeSchedule: matchingSchedule,
          ),
        );
        _repository.setLight(true);
      }
    } else {
      if (state.status != LightingStatus.off) {
        emit(
          state.copyWith(status: LightingStatus.off, clearActiveSchedule: true),
        );
        _repository.setLight(false);
      }
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
