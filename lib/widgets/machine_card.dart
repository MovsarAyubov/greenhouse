import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../blocs/irrigation/irrigation_bloc.dart';
import '../blocs/irrigation/irrigation_event.dart';
import '../models/irrigation_models.dart';
import '../theme/app_theme.dart';
import 'irrigation_schedule_manager.dart';
import 'irrigation_settings_dialog.dart';
import 'tank_widget.dart';

class MachineCard extends StatelessWidget {
  final IrrigationMachine machine;

  const MachineCard({super.key, required this.machine});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: machine.isRunning
                          ? AppTheme.primaryGreen.withOpacity(0.1)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: FaIcon(
                      FontAwesomeIcons.faucetDrip,
                      color: machine.isRunning
                          ? AppTheme.primaryGreen
                          : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        machine.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        machine.isRunning ? 'Active' : 'Idle',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: machine.isRunning
                              ? AppTheme.primaryGreen
                              : AppTheme.textGrey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  Switch.adaptive(
                    value: machine.isRunning,
                    activeColor: AppTheme.primaryGreen,
                    onChanged: (value) {
                      if (value) {
                        context.read<IrrigationBloc>().add(
                          StartMachineProgram(machine.id),
                        );
                      } else {
                        context.read<IrrigationBloc>().add(
                          StopMachineProgram(machine.id),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.settings, color: AppTheme.textGrey),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) =>
                            IrrigationSettingsDialog(machine: machine),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.calendar_month,
                      color: AppTheme.textGrey,
                    ),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) =>
                            IrrigationScheduleManager(machine: machine),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildTargetChip(
                context,
                'Target pH',
                machine.targetPH.toStringAsFixed(1),
                Colors.purple,
              ),
              const SizedBox(width: 12),
              _buildTargetChip(
                context,
                'Target EC',
                machine.targetEC.toStringAsFixed(1),
                Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Tanks
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: machine.tanks.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return TankWidget(tank: machine.tanks[index]);
              },
            ),
          ),
          const SizedBox(height: 24),

          // Status & Queue
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.backgroundWhite,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.water_drop, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      'Статус: ${machine.isRunning ? "Активен" : "Ожидание"}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                if (machine.currentValveId != null) ...[
                  const SizedBox(height: 12),
                  _buildProgressIndicator(context),
                ],
                const SizedBox(height: 8),
                Text(
                  'В очереди: ${machine.queue.length} клапанов',
                  style: TextStyle(color: AppTheme.textGrey),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text(
            'Ручное управление блоками',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: machine.assignedBlocks.map((block) {
              return ActionChip(
                avatar: const Icon(
                  Icons.play_arrow,
                  size: 16,
                  color: Colors.white,
                ),
                label: Text(
                  block.name,
                ), // Names are already "Block X" or similar, maybe translate if needed but "Block" is understandable or I can replace "Block" with "Блок"
                backgroundColor: AppTheme.primaryGreen,
                labelStyle: const TextStyle(color: Colors.white),
                onPressed: machine.isRunning
                    ? null
                    : () {
                        context.read<IrrigationBloc>().add(
                          StartBlock(machine.id, block.id),
                        );
                      },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(BuildContext context) {
    if (machine.currentValveStartTime == null ||
        machine.currentValveDuration == null) {
      return const Text(
        'Полив...',
        style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
      );
    }

    // Find current valve name
    String valveName = 'Клапан ${machine.currentValveId?.substring(0, 4)}';
    for (var block in machine.assignedBlocks) {
      for (var valve in block.valves) {
        if (valve.id == machine.currentValveId) {
          valveName = '${block.name} - ${valve.name}';
          break;
        }
      }
    }

    // Calculate progress
    // Note: In a real app, we'd use a Timer.periodic in a StatefulWidget to update this smoothly.
    // Since this is a StatelessWidget, it updates on Bloc state changes (every second from repo).
    final now = DateTime.now();
    final elapsed = now.difference(machine.currentValveStartTime!).inSeconds;
    final duration = machine.currentValveDuration!;

    // Speed factor 10x
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
              'Полив: $valveName',
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
          backgroundColor: Colors.blue.withOpacity(0.1),
          color: Colors.blue,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }

  Widget _buildTargetChip(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
