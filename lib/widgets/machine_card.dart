import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../blocs/irrigation/irrigation_bloc.dart';
import '../blocs/irrigation/irrigation_event.dart';
import '../models/irrigation_models.dart';
import '../presentation/widgets/machine_progress_indicator.dart';
import '../presentation/widgets/target_chip.dart';
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
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: machine.isRunning
                          ? AppTheme.primaryGreen.withValues(alpha: 0.1)
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
                    activeTrackColor: AppTheme.primaryGreen,
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
              TargetChip(
                label: 'Target pH',
                value: machine.targetPH.toStringAsFixed(1),
                color: Colors.purple,
              ),
              const SizedBox(width: 12),
              TargetChip(
                label: 'Target EC',
                value: machine.targetEC.toStringAsFixed(1),
                color: Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 24),
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
                      'РЎС‚Р°С‚СѓСЃ: ${machine.isRunning ? "РђРєС‚РёРІРµРЅ" : "РћР¶РёРґР°РЅРёРµ"}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                if (machine.currentValveId != null) ...[
                  const SizedBox(height: 12),
                  MachineProgressIndicator(machine: machine),
                ],
                const SizedBox(height: 8),
                Text(
                  'Р’ РѕС‡РµСЂРµРґРё: ${machine.queue.length} РєР»Р°РїР°РЅРѕРІ',
                  style: TextStyle(color: AppTheme.textGrey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Р СѓС‡РЅРѕРµ СѓРїСЂР°РІР»РµРЅРёРµ Р±Р»РѕРєР°РјРё',
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
                label: Text(block.name),
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
}
