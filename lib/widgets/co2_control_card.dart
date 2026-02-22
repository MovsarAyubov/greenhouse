// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../blocs/co2/co2_bloc.dart';
import '../blocs/co2/co2_state.dart';
import '../theme/app_theme.dart';

class Co2ControlCard extends StatelessWidget {
  const Co2ControlCard({super.key});

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<Co2Bloc, Co2State>(
      builder: (context, state) {
        final isActive = state.status != Co2OperationStatus.idle;
        final activeSchedule = state.activeSchedule;

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
                          color: isActive
                              ? AppTheme.primaryGreen.withOpacity(0.1)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: FaIcon(
                          FontAwesomeIcons.smog,
                          color: isActive ? AppTheme.primaryGreen : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CO2 Injection',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            isActive
                                ? 'Active: ${activeSchedule?.startTime.format(context)} - ${activeSchedule?.endTime.format(context)}'
                                : 'System Idle',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppTheme.textGrey),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: state.status == Co2OperationStatus.dosing
                            ? Colors.green.withOpacity(0.1)
                            : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: state.status == Co2OperationStatus.dosing
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                      child: Text(
                        state.status == Co2OperationStatus.dosing
                            ? 'DOSING'
                            : 'PAUSED',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: state.status == Co2OperationStatus.dosing
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                    ),
                ],
              ),

              if (isActive) ...[
                const SizedBox(height: 24),
                // Timer Visualization
                Center(
                  child: Column(
                    children: [
                      Text(
                        _formatTime(state.remainingSeconds),
                        style: Theme.of(context).textTheme.displayMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                              fontFeatures: [
                                const FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                      Text(
                        'until next phase',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                LinearProgressIndicator(
                  value: state.status == Co2OperationStatus.dosing
                      ? 1 -
                            (state.remainingSeconds /
                                (activeSchedule!.workDurationMinutes * 60))
                      : 1 -
                            (state.remainingSeconds /
                                (activeSchedule!.pauseDurationMinutes * 60)),
                  backgroundColor: Colors.grey.shade100,
                  color: state.status == Co2OperationStatus.dosing
                      ? AppTheme.primaryGreen
                      : Colors.orange,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
