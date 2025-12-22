import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

enum TankType { acid, base, fertilizerA, fertilizerB }

class Tank {
  final String id;
  final String name;
  final TankType type;
  final double capacity; // Liters
  final double currentLevel; // Liters
  final bool isReserve;

  const Tank({
    required this.id,
    required this.name,
    required this.type,
    required this.capacity,
    required this.currentLevel,
    this.isReserve = false,
  });

  Tank copyWith({
    String? id,
    String? name,
    TankType? type,
    double? capacity,
    double? currentLevel,
    bool? isReserve,
  }) {
    return Tank(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      capacity: capacity ?? this.capacity,
      currentLevel: currentLevel ?? this.currentLevel,
      isReserve: isReserve ?? this.isReserve,
    );
  }

  double get fillPercentage => (currentLevel / capacity).clamp(0.0, 1.0);
  bool get isEmpty => currentLevel <= 0;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.index,
      'capacity': capacity,
      'currentLevel': currentLevel,
      'isReserve': isReserve,
    };
  }

  factory Tank.fromJson(Map<String, dynamic> json) {
    return Tank(
      id: json['id'],
      name: json['name'],
      type: TankType.values[json['type']],
      capacity: json['capacity'],
      currentLevel: json['currentLevel'],
      isReserve: json['isReserve'],
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    type,
    capacity,
    currentLevel,
    isReserve,
  ];
}

class IrrigationValve extends Equatable {
  final String id;
  final String name;
  final int dripperCount;
  final double area; // m2
  final double targetVolumePerDripper; // Liters
  final bool isWatering;

  const IrrigationValve({
    required this.id,
    required this.name,
    required this.dripperCount,
    required this.area,
    required this.targetVolumePerDripper,
    this.isWatering = false,
  });

  IrrigationValve copyWith({
    String? id,
    String? name,
    int? dripperCount,
    double? area,
    double? targetVolumePerDripper,
    bool? isWatering,
  }) {
    return IrrigationValve(
      id: id ?? this.id,
      name: name ?? this.name,
      dripperCount: dripperCount ?? this.dripperCount,
      area: area ?? this.area,
      targetVolumePerDripper:
          targetVolumePerDripper ?? this.targetVolumePerDripper,
      isWatering: isWatering ?? this.isWatering,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'dripperCount': dripperCount,
      'area': area,
      'targetVolumePerDripper': targetVolumePerDripper,
      'isWatering': isWatering,
    };
  }

  factory IrrigationValve.fromJson(Map<String, dynamic> json) {
    return IrrigationValve(
      id: json['id'],
      name: json['name'],
      dripperCount: json['dripperCount'],
      area: json['area'],
      targetVolumePerDripper: json['targetVolumePerDripper'],
      isWatering: json['isWatering'] ?? false,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    dripperCount,
    area,
    targetVolumePerDripper,
    isWatering,
  ];
}

class IrrigationBlock extends Equatable {
  final String id;
  final String name;
  final List<IrrigationValve> valves;

  const IrrigationBlock({
    required this.id,
    required this.name,
    required this.valves,
  });

  IrrigationBlock copyWith({
    String? id,
    String? name,
    List<IrrigationValve>? valves,
  }) {
    return IrrigationBlock(
      id: id ?? this.id,
      name: name ?? this.name,
      valves: valves ?? this.valves,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'valves': valves.map((v) => v.toJson()).toList(),
    };
  }

  factory IrrigationBlock.fromJson(Map<String, dynamic> json) {
    return IrrigationBlock(
      id: json['id'],
      name: json['name'],
      valves: (json['valves'] as List)
          .map((v) => IrrigationValve.fromJson(v))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [id, name, valves];
}

class IrrigationMachine {
  final String id;
  final String name;
  final List<Tank> tanks;
  final List<IrrigationBlock> assignedBlocks;
  final double pumpCapacity; // Liters per hour
  final double targetPH;
  final double targetEC;
  final bool isRunning;
  final String? currentValveId; // ID of the valve currently being watered
  final DateTime? currentValveStartTime;
  final int? currentValveDuration; // in seconds
  final List<String> queue; // List of Valve IDs waiting
  final List<IrrigationScheduleItem> schedules;
  final DateTime? lastRunTime;

  const IrrigationMachine({
    required this.id,
    required this.name,
    required this.tanks,
    required this.assignedBlocks,
    this.pumpCapacity = 1000,
    this.targetPH = 6.0,
    this.targetEC = 2.0,
    this.isRunning = false,
    this.currentValveId,
    this.currentValveStartTime,
    this.currentValveDuration,
    this.queue = const [],
    this.schedules = const [],
    this.lastRunTime,
  });

  IrrigationMachine copyWith({
    String? id,
    String? name,
    List<Tank>? tanks,
    List<IrrigationBlock>? assignedBlocks,
    double? pumpCapacity,
    double? targetPH,
    double? targetEC,
    bool? isRunning,
    String? currentValveId,
    bool clearCurrentValveId = false,
    DateTime? currentValveStartTime,
    bool clearCurrentValveStartTime = false,
    int? currentValveDuration,
    bool clearCurrentValveDuration = false,
    List<String>? queue,
    List<IrrigationScheduleItem>? schedules,
    DateTime? lastRunTime,
  }) {
    return IrrigationMachine(
      id: id ?? this.id,
      name: name ?? this.name,
      tanks: tanks ?? this.tanks,
      assignedBlocks: assignedBlocks ?? this.assignedBlocks,
      pumpCapacity: pumpCapacity ?? this.pumpCapacity,
      targetPH: targetPH ?? this.targetPH,
      targetEC: targetEC ?? this.targetEC,
      isRunning: isRunning ?? this.isRunning,
      currentValveId: clearCurrentValveId
          ? null
          : (currentValveId ?? this.currentValveId),
      currentValveStartTime: clearCurrentValveStartTime
          ? null
          : (currentValveStartTime ?? this.currentValveStartTime),
      currentValveDuration: clearCurrentValveDuration
          ? null
          : (currentValveDuration ?? this.currentValveDuration),
      queue: queue ?? this.queue,
      schedules: schedules ?? this.schedules,
      lastRunTime: lastRunTime ?? this.lastRunTime,
    );
  }

  // Helpers to get active tanks
  List<Tank> get activeFertilizerTanks {
    // Logic: If main tanks are empty, return reserve.
    // Assuming we have 2 main (A, B) and 2 reserve (A, B).
    // We need to find Main A and Main B.
    final mainA = tanks.firstWhere(
      (t) => t.type == TankType.fertilizerA && !t.isReserve,
    );
    final mainB = tanks.firstWhere(
      (t) => t.type == TankType.fertilizerB && !t.isReserve,
    );

    if (mainA.isEmpty || mainB.isEmpty) {
      return tanks
          .where(
            (t) =>
                t.isReserve &&
                (t.type == TankType.fertilizerA ||
                    t.type == TankType.fertilizerB),
          )
          .toList();
    }
    return [mainA, mainB];
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'tanks': tanks.map((t) => t.toJson()).toList(),
      'assignedBlocks': assignedBlocks.map((b) => b.toJson()).toList(),
      'pumpCapacity': pumpCapacity,
      'targetPH': targetPH,
      'targetEC': targetEC,
      'isRunning': isRunning,
      'currentValveId': currentValveId,
      'currentValveStartTime': currentValveStartTime?.toIso8601String(),
      'currentValveDuration': currentValveDuration,
      'queue': queue,
      'schedules': schedules.map((s) => s.toJson()).toList(),
      'lastRunTime': lastRunTime?.toIso8601String(),
    };
  }

  factory IrrigationMachine.fromJson(Map<String, dynamic> json) {
    return IrrigationMachine(
      id: json['id'],
      name: json['name'],
      tanks: (json['tanks'] as List).map((t) => Tank.fromJson(t)).toList(),
      assignedBlocks: (json['assignedBlocks'] as List)
          .map((b) => IrrigationBlock.fromJson(b))
          .toList(),
      pumpCapacity: json['pumpCapacity'],
      targetPH: json['targetPH'],
      targetEC: json['targetEC'],
      isRunning: json['isRunning'],
      currentValveId: json['currentValveId'],
      currentValveStartTime: json['currentValveStartTime'] != null
          ? DateTime.parse(json['currentValveStartTime'])
          : null,
      currentValveDuration: json['currentValveDuration'],
      queue: List<String>.from(json['queue']),
      schedules: (json['schedules'] as List)
          .map((s) => IrrigationScheduleItem.fromJson(s))
          .toList(),
      lastRunTime: json['lastRunTime'] != null
          ? DateTime.parse(json['lastRunTime'])
          : null,
    );
  }
}

class IrrigationScheduleItem {
  final String id;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final int pauseMinutes;
  final bool isEnabled;

  const IrrigationScheduleItem({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.pauseMinutes,
    this.isEnabled = true,
  });

  IrrigationScheduleItem copyWith({
    String? id,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    int? pauseMinutes,
    bool? isEnabled,
  }) {
    return IrrigationScheduleItem(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      pauseMinutes: pauseMinutes ?? this.pauseMinutes,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startTimeHour': startTime.hour,
      'startTimeMinute': startTime.minute,
      'endTimeHour': endTime.hour,
      'endTimeMinute': endTime.minute,
      'pauseMinutes': pauseMinutes,
      'isEnabled': isEnabled,
    };
  }

  factory IrrigationScheduleItem.fromJson(Map<String, dynamic> json) {
    return IrrigationScheduleItem(
      id: json['id'],
      startTime: TimeOfDay(
        hour: json['startTimeHour'],
        minute: json['startTimeMinute'],
      ),
      endTime: TimeOfDay(
        hour: json['endTimeHour'],
        minute: json['endTimeMinute'],
      ),
      pauseMinutes: json['pauseMinutes'],
      isEnabled: json['isEnabled'],
    );
  }
}
