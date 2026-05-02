import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

enum LightingStatus { on, off }

class LightingScheduleItem extends Equatable {
  final String id;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final bool isEnabled;

  const LightingScheduleItem({
    required this.id,
    required this.startTime,
    required this.endTime,
    this.isEnabled = true,
  });

  LightingScheduleItem copyWith({
    String? id,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    bool? isEnabled,
  }) {
    return LightingScheduleItem(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startTime': '${startTime.hour}:${startTime.minute}',
      'endTime': '${endTime.hour}:${endTime.minute}',
      'isEnabled': isEnabled,
    };
  }

  factory LightingScheduleItem.fromJson(Map<String, dynamic> json) {
    final startParts = (json['startTime'] as String).split(':');
    final endParts = (json['endTime'] as String).split(':');
    return LightingScheduleItem(
      id: json['id'],
      startTime: TimeOfDay(
        hour: int.parse(startParts[0]),
        minute: int.parse(startParts[1]),
      ),
      endTime: TimeOfDay(
        hour: int.parse(endParts[0]),
        minute: int.parse(endParts[1]),
      ),
      isEnabled: json['isEnabled'] ?? true,
    );
  }

  @override
  List<Object?> get props => [id, startTime, endTime, isEnabled];
}
