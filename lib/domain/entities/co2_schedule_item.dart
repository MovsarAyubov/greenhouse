import 'package:flutter/material.dart';

class Co2ScheduleItem {
  final String id;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final int workDurationMinutes;
  final int pauseDurationMinutes;
  final bool isEnabled;

  Co2ScheduleItem({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.workDurationMinutes,
    required this.pauseDurationMinutes,
    this.isEnabled = true,
  });

  Co2ScheduleItem copyWith({
    String? id,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    int? workDurationMinutes,
    int? pauseDurationMinutes,
    bool? isEnabled,
  }) {
    return Co2ScheduleItem(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      workDurationMinutes: workDurationMinutes ?? this.workDurationMinutes,
      pauseDurationMinutes: pauseDurationMinutes ?? this.pauseDurationMinutes,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}
