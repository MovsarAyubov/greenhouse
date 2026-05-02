import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/entities/irrigation_models.dart';

class MachineProgressIndicator extends StatefulWidget {
  final IrrigationMachine machine;

  const MachineProgressIndicator({super.key, required this.machine});

  @override
  State<MachineProgressIndicator> createState() =>
      _MachineProgressIndicatorState();
}

class _MachineProgressIndicatorState extends State<MachineProgressIndicator> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant MachineProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.machine.id != widget.machine.id ||
        oldWidget.machine.currentValveId != widget.machine.currentValveId ||
        oldWidget.machine.currentValveStartTime !=
            widget.machine.currentValveStartTime) {
      _startTimerIfNeeded();
    }
  }

  void _startTimerIfNeeded() {
    _timer?.cancel();
    if (widget.machine.currentValveStartTime != null &&
        widget.machine.currentValveDuration != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final machine = widget.machine;
    if (machine.currentValveStartTime == null ||
        machine.currentValveDuration == null) {
      return const Text(
        'РџРѕР»РёРІ...',
        style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
      );
    }

    String valveName =
        'РљР»Р°РїР°РЅ ${machine.currentValveId?.substring(0, 4)}';
    for (final block in machine.assignedBlocks) {
      for (final valve in block.valves) {
        if (valve.id == machine.currentValveId) {
          valveName = '${block.name} - ${valve.name}';
          break;
        }
      }
    }

    final now = DateTime.now();
    final elapsed = now.difference(machine.currentValveStartTime!).inSeconds;
    final duration = machine.currentValveDuration!;
    const speedFactor = 10;
    final effectiveElapsed = elapsed * speedFactor;
    final progress = (effectiveElapsed / duration).clamp(0.0, 1.0);
    final remainingSeconds = (duration - effectiveElapsed) / speedFactor;
    final remaining = remainingSeconds > 0 ? remainingSeconds.round() : 0;
    final remainingStr = remaining > 0
        ? '${(remaining ~/ 60).toString().padLeft(2, '0')}:${(remaining % 60).toString().padLeft(2, '0')}'
        : '00:00';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'РџРѕР»РёРІ: $valveName',
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              remainingStr,
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.blue.withValues(alpha: 0.1),
          color: Colors.blue,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
}
