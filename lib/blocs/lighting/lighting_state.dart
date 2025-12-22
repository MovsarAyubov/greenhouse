import 'package:equatable/equatable.dart';
import '../../models/lighting_models.dart';

class LightingState extends Equatable {
  final LightingStatus status;
  final List<LightingScheduleItem> schedules;
  final LightingScheduleItem? activeSchedule;
  final Map<int, bool> blockStatus;

  const LightingState({
    this.status = LightingStatus.off,
    this.schedules = const [],
    this.activeSchedule,
    this.blockStatus = const {},
  });

  LightingState copyWith({
    LightingStatus? status,
    List<LightingScheduleItem>? schedules,
    LightingScheduleItem? activeSchedule,
    bool clearActiveSchedule = false,
    Map<int, bool>? blockStatus,
  }) {
    return LightingState(
      status: status ?? this.status,
      schedules: schedules ?? this.schedules,
      activeSchedule: clearActiveSchedule
          ? null
          : (activeSchedule ?? this.activeSchedule),
      blockStatus: blockStatus ?? this.blockStatus,
    );
  }

  @override
  List<Object?> get props => [status, schedules, activeSchedule, blockStatus];
}
