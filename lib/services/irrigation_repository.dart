import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/irrigation_models.dart';
import 'climate_repository.dart';

class IrrigationRepository {
  final ClimateRepository _climateRepository;
  final _controller = StreamController<List<IrrigationMachine>>.broadcast();
  List<IrrigationMachine> _machines = [];
  Timer? _simulationTimer;
  static const String _storageKey = 'irrigation_state';

  Stream<List<IrrigationMachine>> get machinesStream => _controller.stream;

  IrrigationRepository({required ClimateRepository climateRepository})
    : _climateRepository = climateRepository {
    _loadState().then((_) {
      if (_machines.isEmpty) {
        _initializeMachines();
      }
      _startSimulation();
    });
  }

  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String jsonStr = jsonEncode(
        _machines.map((m) => m.toJson()).toList(),
      );
      await prefs.setString(_storageKey, jsonStr);
    } catch (e) {
      debugPrint('Error saving irrigation state: $e');
    }
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null) {
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        _machines = jsonList.map((j) => IrrigationMachine.fromJson(j)).toList();
        _controller.add(List.from(_machines));
      }
    } catch (e) {
      debugPrint('Error loading irrigation state: $e');
    }
  }

  void _initializeMachines() {
    // Helper to create tanks
    List<Tank> createTanks(String prefix) {
      return [
        Tank(
          id: const Uuid().v4(),
          name: 'Acid',
          type: TankType.acid,
          capacity: 1000,
          currentLevel: 800,
        ),
        Tank(
          id: const Uuid().v4(),
          name: 'Base',
          type: TankType.base,
          capacity: 1000,
          currentLevel: 800,
        ),
        Tank(
          id: const Uuid().v4(),
          name: 'Fert A Main',
          type: TankType.fertilizerA,
          capacity: 2000,
          currentLevel: 1500,
        ),
        Tank(
          id: const Uuid().v4(),
          name: 'Fert B Main',
          type: TankType.fertilizerB,
          capacity: 2000,
          currentLevel: 1500,
        ),
        Tank(
          id: const Uuid().v4(),
          name: 'Fert A Res',
          type: TankType.fertilizerA,
          capacity: 2000,
          currentLevel: 2000,
          isReserve: true,
        ),
        Tank(
          id: const Uuid().v4(),
          name: 'Fert B Res',
          type: TankType.fertilizerB,
          capacity: 2000,
          currentLevel: 2000,
          isReserve: true,
        ),
      ];
    }

    // Helper to create blocks
    List<IrrigationBlock> createBlocks(int start, int end) {
      return List.generate(end - start + 1, (index) {
        final blockNum = start + index;
        return IrrigationBlock(
          id: const Uuid().v4(),
          name: 'Блок $blockNum',
          valves: [
            IrrigationValve(
              id: const Uuid().v4(),
              name: 'Клапан 1',
              dripperCount: 1000,
              area: 500,
              targetVolumePerDripper: 0.1, // 100ml
            ),
            IrrigationValve(
              id: const Uuid().v4(),
              name: 'Клапан 2',
              dripperCount: 1000,
              area: 500,
              targetVolumePerDripper: 0.1,
            ),
          ],
        );
      });
    }

    _machines = [
      IrrigationMachine(
        id: 'machine_1',
        name: 'Узел 1 (Блоки 1-3)',
        tanks: createTanks('M1'),
        assignedBlocks: createBlocks(1, 3),
        pumpCapacity: 10000, // 10,000 L/h
      ),
      IrrigationMachine(
        id: 'machine_2',
        name: 'Узел 2 (Блоки 4-6)',
        tanks: createTanks('M2'),
        assignedBlocks: createBlocks(4, 6),
        pumpCapacity: 10000,
      ),
    ];
    _controller.add(List.from(_machines));
  }

  void startProgram(String machineId) {
    final machineIndex = _machines.indexWhere((m) => m.id == machineId);
    if (machineIndex == -1) return;

    var machine = _machines[machineIndex];
    if (machine.isRunning) return; // Already running

    // Build Queue: Add all valves from all assigned blocks sequentially
    List<String> queue = [];
    for (var block in machine.assignedBlocks) {
      for (var valve in block.valves) {
        queue.add(valve.id);
      }
    }

    if (queue.isEmpty) return;

    // Start first valve
    final firstValveId = queue.removeAt(0);

    _machines[machineIndex] = machine.copyWith(
      isRunning: true,
      queue: queue,
      currentValveId: firstValveId,
    );
    _updateValveStatus(machineId, firstValveId, true);
    _controller.add(List.from(_machines));
    _saveState();
  }

  void stopProgram(String machineId) {
    final machineIndex = _machines.indexWhere((m) => m.id == machineId);
    if (machineIndex == -1) return;

    var machine = _machines[machineIndex];

    // Reset valve status
    if (machine.currentValveId != null) {
      _updateValveStatus(machineId, machine.currentValveId!, false);
    }

    _machines[machineIndex] = machine.copyWith(
      isRunning: false,
      queue: [],
      clearCurrentValveId: true,
      clearCurrentValveDuration: true,
      clearCurrentValveStartTime: true,
    );
    _controller.add(List.from(_machines));
    _saveState();
  }

  void _updateValveStatus(String machineId, String valveId, bool isWatering) {
    final machineIndex = _machines.indexWhere((m) => m.id == machineId);
    var machine = _machines[machineIndex];

    List<IrrigationBlock> newBlocks = [];
    for (var block in machine.assignedBlocks) {
      List<IrrigationValve> newValves = [];
      for (var valve in block.valves) {
        if (valve.id == valveId) {
          newValves.add(valve.copyWith(isWatering: isWatering));
        } else {
          newValves.add(valve);
        }
      }
      newBlocks.add(block.copyWith(valves: newValves));
    }
    _machines[machineIndex] = machine.copyWith(assignedBlocks: newBlocks);

    // Send command to hardware
    // Assuming valveId is int or can be parsed. If UUID, we need a mapping.
    // For now, let's hash it or use a placeholder if not int.
    // Ideally, Valve ID should be int for Modbus.
    // Let's just print/send for now.
    try {
      // Simple hash or parse if possible. In real app, use mapped ID.
      int vId = valveId.hashCode;
      _climateRepository.setIrrigationValve(vId, isWatering);
    } catch (e) {
      print('Error sending valve command: $e');
    }
  }

  void updateMachine(IrrigationMachine updatedMachine) {
    final index = _machines.indexWhere((m) => m.id == updatedMachine.id);
    if (index != -1) {
      _machines[index] = updatedMachine;
      _controller.add(List.from(_machines));
      _saveState();
    }
  }

  void addSchedule(String machineId, IrrigationScheduleItem schedule) {
    final index = _machines.indexWhere((m) => m.id == machineId);
    if (index != -1) {
      final machine = _machines[index];
      final newSchedules = List<IrrigationScheduleItem>.from(machine.schedules)
        ..add(schedule);
      _machines[index] = machine.copyWith(schedules: newSchedules);
      _controller.add(List.from(_machines));
      _saveState();
    }
  }

  void updateSchedule(String machineId, IrrigationScheduleItem schedule) {
    final index = _machines.indexWhere((m) => m.id == machineId);
    if (index != -1) {
      final machine = _machines[index];
      final newSchedules = machine.schedules
          .map((s) => s.id == schedule.id ? schedule : s)
          .toList();
      _machines[index] = machine.copyWith(schedules: newSchedules);
      _controller.add(List.from(_machines));
    }
  }

  void deleteSchedule(String machineId, String scheduleId) {
    final index = _machines.indexWhere((m) => m.id == machineId);
    if (index != -1) {
      final machine = _machines[index];
      final newSchedules = machine.schedules
          .where((s) => s.id != scheduleId)
          .toList();
      _machines[index] = machine.copyWith(schedules: newSchedules);
      _controller.add(List.from(_machines));
    }
  }

  // Map to track start time of current valve for each machine
  final Map<String, DateTime> _valveStartTimes = {};

  void startBlock(String machineId, String blockId) {
    final machineIndex = _machines.indexWhere((m) => m.id == machineId);
    if (machineIndex == -1) return;

    var machine = _machines[machineIndex];
    if (machine.isRunning) return;

    // Find block
    final block = machine.assignedBlocks.firstWhere(
      (b) => b.id == blockId,
      orElse: () => machine.assignedBlocks.first,
    );

    // Build Queue for just this block
    List<String> queue = [];
    for (var valve in block.valves) {
      queue.add(valve.id);
    }

    if (queue.isEmpty) return;

    final firstValveId = queue.removeAt(0);

    _machines[machineIndex] = machine.copyWith(
      isRunning: true,
      queue: queue,
      currentValveId: firstValveId,
    );
    _updateValveStatus(machineId, firstValveId, true);
    _controller.add(List.from(_machines));
  }

  void _startSimulation() {
    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      final timeOfDay = TimeOfDay.fromDateTime(now);

      for (int i = 0; i < _machines.length; i++) {
        var machine = _machines[i];

        // --- Scheduling Logic ---
        if (!machine.isRunning) {
          // Check schedules
          for (var schedule in machine.schedules) {
            if (!schedule.isEnabled) continue;

            // Check if current time is within window
            final startMinutes =
                schedule.startTime.hour * 60 + schedule.startTime.minute;
            final endMinutes =
                schedule.endTime.hour * 60 + schedule.endTime.minute;
            final currentMinutes = timeOfDay.hour * 60 + timeOfDay.minute;

            bool isWithinWindow;
            if (startMinutes < endMinutes) {
              // Standard window (e.g. 08:00 - 20:00)
              isWithinWindow =
                  currentMinutes >= startMinutes && currentMinutes < endMinutes;
            } else {
              // Midnight crossing (e.g. 20:00 - 08:00)
              // Valid if AFTER start OR BEFORE end
              isWithinWindow =
                  currentMinutes >= startMinutes || currentMinutes < endMinutes;
            }

            if (isWithinWindow) {
              // Check pause interval
              bool shouldStart = false;
              if (machine.lastRunTime == null) {
                shouldStart = true;
              } else {
                final diffMinutes = now
                    .difference(machine.lastRunTime!)
                    .inMinutes;
                if (diffMinutes >= schedule.pauseMinutes) {
                  shouldStart = true;
                }
              }

              if (shouldStart) {
                startProgram(machine.id);
                // Refresh machine ref after startProgram
                machine = _machines[i];
                break; // Only start once
              }
            }
          }
        }
        // ------------------------

        if (!machine.isRunning || machine.currentValveId == null) {
          _valveStartTimes.remove(machine.id);
          continue;
        }

        // 1. Calculate Duration
        // Find current valve
        IrrigationValve? currentValve;
        for (var block in machine.assignedBlocks) {
          for (var valve in block.valves) {
            if (valve.id == machine.currentValveId) {
              currentValve = valve;
              break;
            }
          }
        }

        if (currentValve == null) {
          _advanceQueue(machine.id);
          continue;
        }

        // Formula: Duration (hours) = Total Volume (L) / Pump Capacity (L/h)
        // Total Volume = Drippers * VolPerDripper
        final totalVolume =
            currentValve.dripperCount * currentValve.targetVolumePerDripper;
        final durationHours =
            totalVolume /
            (machine.pumpCapacity > 0 ? machine.pumpCapacity : 1000);
        final durationSeconds = (durationHours * 3600).round();

        // Update machine with duration if not set
        if (machine.currentValveDuration == null) {
          machine = machine.copyWith(currentValveDuration: durationSeconds);
          _machines[i] = machine;
          // We don't emit here to avoid spamming, will emit on next tick or status change
        }

        // 2. Check Time
        final startTime = _valveStartTimes.putIfAbsent(machine.id, () {
          // If starting new valve, update machine state
          final now = DateTime.now();
          _machines[i] = machine.copyWith(currentValveStartTime: now);
          return now;
        });

        // Ensure start time is in sync if it was loaded from state (future implementation)
        if (machine.currentValveStartTime == null) {
          _machines[i] = machine.copyWith(currentValveStartTime: startTime);
          machine = _machines[i];
        }

        final elapsed = DateTime.now().difference(startTime).inSeconds;

        // Speed up factor for demo (e.g. 10x speed)
        const speedFactor = 10;

        if (elapsed * speedFactor >= durationSeconds) {
          _valveStartTimes.remove(machine.id);
          _advanceQueue(machine.id);
          // Refresh machine reference
          machine = _machines[i];
        }

        // 3. Consume Tanks
        // Consumption rate depends on flow rate and injection ratio (simplified here)
        List<Tank> newTanks = List.from(machine.tanks);

        newTanks = newTanks.map((tank) {
          // Consume 0.1L per second * speedFactor (Just a simulation value)
          double consumption = 0.05 * speedFactor;

          if (tank.type == TankType.acid || tank.type == TankType.base) {
            return tank.copyWith(
              currentLevel: (tank.currentLevel - consumption).clamp(
                0,
                tank.capacity,
              ),
            );
          }

          bool isTargetFert =
              (tank.type == TankType.fertilizerA ||
              tank.type == TankType.fertilizerB);
          if (isTargetFert) {
            return tank.copyWith(
              currentLevel: (tank.currentLevel - consumption).clamp(
                0,
                tank.capacity,
              ),
            );
          }
          return tank;
        }).toList();

        _machines[i] = machine.copyWith(tanks: newTanks);
      }
      _controller.add(List.from(_machines));
    });
  }

  void _advanceQueue(String machineId) {
    final machineIndex = _machines.indexWhere((m) => m.id == machineId);
    var machine = _machines[machineIndex];

    // Stop current
    if (machine.currentValveId != null) {
      _updateValveStatus(machineId, machine.currentValveId!, false);
      // Refresh machine after update
      machine = _machines[machineIndex];
    }

    if (machine.queue.isEmpty) {
      // Program finished
      _machines[machineIndex] = machine.copyWith(
        isRunning: false,
        clearCurrentValveId: true,
        clearCurrentValveDuration: true,
        clearCurrentValveStartTime: true,
        lastRunTime: DateTime.now(),
      );
    } else {
      // Next valve
      List<String> newQueue = List.from(machine.queue);
      final nextValveId = newQueue.removeAt(0);

      _machines[machineIndex] = machine.copyWith(
        queue: newQueue,
        currentValveId: nextValveId,
        clearCurrentValveDuration: true, // Will be recalculated
        clearCurrentValveStartTime: true, // Will be reset
      );
      _updateValveStatus(machineId, nextValveId, true);
    }
    _saveState();
  }

  void dispose() {
    _simulationTimer?.cancel();
    _controller.close();
  }
}
