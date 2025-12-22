import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:greenhouse/blocs/lighting/lighting_event.dart';
import '../blocs/lighting/lighting_bloc.dart';
import '../blocs/lighting/lighting_state.dart';
import '../models/lighting_models.dart';
import '../theme/app_theme.dart';
import 'lighting_schedule_manager.dart';

class LightingControlCard extends StatelessWidget {
  const LightingControlCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LightingBloc, LightingState>(
      builder: (context, state) {
        final isOn = state.status == LightingStatus.on;

        return Container(
          padding: const EdgeInsets.all(24),
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
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.lightbulb,
                          color: Colors.orange,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'Освещение',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isOn
                          ? Colors.orange
                          : Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isOn ? 'ВКЛ' : 'ВЫКЛ',
                      style: TextStyle(
                        color: isOn ? Colors.white : AppTheme.textGrey,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (state.activeSchedule != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundWhite,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        FontAwesomeIcons.clock,
                        size: 16,
                        color: AppTheme.textGrey,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Активное расписание',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textGrey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${state.activeSchedule!.startTime.format(context)} - ${state.activeSchedule!.endTime.format(context)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              const Divider(height: 32),
              const Text(
                'Ручное управление блоками',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: List.generate(6, (index) {
                  final blockId = index + 1;
                  final isBlockOn = state.blockStatus[blockId] ?? false;

                  return InkWell(
                    onTap: () {
                      context.read<LightingBloc>().add(
                        ToggleBlockLight(blockId),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 80,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isBlockOn
                            ? Colors.orange
                            : AppTheme.backgroundWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isBlockOn
                              ? Colors.orange
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.lightbulb,
                            color: isBlockOn ? Colors.white : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Блок $blockId',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isBlockOn
                                  ? Colors.white
                                  : AppTheme.textGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => const LightingScheduleManager(),
                    );
                  },
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: const Text('Настроить расписание'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: Colors.orange.withOpacity(0.5)),
                    foregroundColor: Colors.orange,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
