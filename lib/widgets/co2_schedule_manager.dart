import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:uuid/uuid.dart';
import '../blocs/co2/co2_bloc.dart';
import '../blocs/co2/co2_event.dart';
import '../blocs/co2/co2_state.dart';
import '../models/co2_schedule_item.dart';
import '../theme/app_theme.dart';

class Co2ScheduleManager extends StatelessWidget {
  const Co2ScheduleManager({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<Co2Bloc, Co2State>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Daily Schedule',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => _showAddEditDialog(context),
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (state.schedules.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    'No schedules set. Add one to start automation.',
                    style: TextStyle(color: AppTheme.textGrey),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: state.schedules.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final schedule = state.schedules[index];
                  final isActive = state.activeSchedule?.id == schedule.id;

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: isActive
                          ? Border.all(color: AppTheme.primaryGreen, width: 2)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppTheme.primaryGreen
                              : Colors.grey.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: FaIcon(
                          FontAwesomeIcons.clock,
                          size: 18,
                          color: isActive ? Colors.white : Colors.grey,
                        ),
                      ),
                      title: Text(
                        '${schedule.startTime.format(context)} - ${schedule.endTime.format(context)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Dose: ${schedule.workDurationMinutes}m / Pause: ${schedule.pauseDurationMinutes}m',
                        style: TextStyle(color: AppTheme.textGrey),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch.adaptive(
                            value: schedule.isEnabled,
                            activeColor: AppTheme.primaryGreen,
                            onChanged: (val) {
                              context.read<Co2Bloc>().add(
                                UpdateCo2Schedule(
                                  schedule.copyWith(isEnabled: val),
                                ),
                              );
                            },
                          ),
                          PopupMenuButton(
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                            onSelected: (value) {
                              if (value == 'edit') {
                                _showAddEditDialog(context, schedule: schedule);
                              } else if (value == 'delete') {
                                context.read<Co2Bloc>().add(
                                  DeleteCo2Schedule(schedule.id),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  void _showAddEditDialog(BuildContext context, {Co2ScheduleItem? schedule}) {
    showDialog(
      context: context,
      builder: (context) => _ScheduleDialog(schedule: schedule),
    );
  }
}

class _ScheduleDialog extends StatefulWidget {
  final Co2ScheduleItem? schedule;

  const _ScheduleDialog({this.schedule});

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late double _workDuration;
  late double _pauseDuration;

  @override
  void initState() {
    super.initState();
    _startTime =
        widget.schedule?.startTime ?? const TimeOfDay(hour: 9, minute: 0);
    _endTime = widget.schedule?.endTime ?? const TimeOfDay(hour: 17, minute: 0);
    _workDuration = widget.schedule?.workDurationMinutes.toDouble() ?? 15;
    _pauseDuration = widget.schedule?.pauseDurationMinutes.toDouble() ?? 15;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.schedule == null ? 'Add Schedule' : 'Edit Schedule'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildTimePicker(
                    context,
                    'Start',
                    _startTime,
                    (val) => setState(() => _startTime = val),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTimePicker(
                    context,
                    'End',
                    _endTime,
                    (val) => setState(() => _endTime = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSlider(
              'Dosing (min)',
              _workDuration,
              (val) => setState(() => _workDuration = val),
            ),
            const SizedBox(height: 16),
            _buildSlider(
              'Pause (min)',
              _pauseDuration,
              (val) => setState(() => _pauseDuration = val),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final newItem = Co2ScheduleItem(
              id: widget.schedule?.id ?? const Uuid().v4(),
              startTime: _startTime,
              endTime: _endTime,
              workDurationMinutes: _workDuration.toInt(),
              pauseDurationMinutes: _pauseDuration.toInt(),
              isEnabled: widget.schedule?.isEnabled ?? true,
            );

            if (widget.schedule == null) {
              context.read<Co2Bloc>().add(AddCo2Schedule(newItem));
            } else {
              context.read<Co2Bloc>().add(UpdateCo2Schedule(newItem));
            }
            Navigator.pop(context);
          },
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildTimePicker(
    BuildContext context,
    String label,
    TimeOfDay time,
    ValueChanged<TimeOfDay> onTimeChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            final newTime = await showTimePicker(
              context: context,
              initialTime: time,
            );
            if (newTime != null) onTimeChanged(newTime);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Text(
                  time.format(context),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                const Icon(Icons.access_time, size: 16, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(
              '${value.toInt()}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Slider(
          value: value,
          min: 1,
          max: 60,
          activeColor: AppTheme.primaryGreen,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
