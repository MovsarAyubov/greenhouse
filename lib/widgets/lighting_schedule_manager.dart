import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:uuid/uuid.dart';
import '../blocs/lighting/lighting_bloc.dart';
import '../blocs/lighting/lighting_event.dart';
import '../blocs/lighting/lighting_state.dart';
import '../models/lighting_models.dart';
import '../theme/app_theme.dart';

class LightingScheduleManager extends StatelessWidget {
  const LightingScheduleManager({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 600,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Расписание освещения',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: BlocBuilder<LightingBloc, LightingState>(
                builder: (context, state) {
                  if (state.schedules.isEmpty) {
                    return Center(
                      child: Text(
                        'Нет активных расписаний',
                        style: TextStyle(color: AppTheme.textGrey),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: state.schedules.length,
                    itemBuilder: (context, index) {
                      final schedule = state.schedules[index];
                      return _buildScheduleItem(context, schedule);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _showEditDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Добавить расписание'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleItem(
    BuildContext context,
    LightingScheduleItem schedule,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: schedule.isEnabled
              ? Colors.orange.withOpacity(0.3)
              : Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: schedule.isEnabled
                    ? Colors.orange.withOpacity(0.1)
                    : Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                FontAwesomeIcons.lightbulb,
                color: schedule.isEnabled ? Colors.orange : Colors.grey,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                '${schedule.startTime.format(context)} - ${schedule.endTime.format(context)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ),
            Switch.adaptive(
              value: schedule.isEnabled,
              activeColor: Colors.orange,
              onChanged: (value) {
                context.read<LightingBloc>().add(
                  UpdateLightingSchedule(schedule.copyWith(isEnabled: value)),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: AppTheme.textGrey),
              onPressed: () => _showEditDialog(context, schedule: schedule),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: () {
                context.read<LightingBloc>().add(
                  DeleteLightingSchedule(schedule.id),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, {LightingScheduleItem? schedule}) {
    showDialog(
      context: context,
      builder: (context) => _ScheduleEditDialog(schedule: schedule),
    );
  }
}

class _ScheduleEditDialog extends StatefulWidget {
  final LightingScheduleItem? schedule;

  const _ScheduleEditDialog({this.schedule});

  @override
  State<_ScheduleEditDialog> createState() => _ScheduleEditDialogState();
}

class _ScheduleEditDialogState extends State<_ScheduleEditDialog> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;

  @override
  void initState() {
    super.initState();
    _startTime =
        widget.schedule?.startTime ?? const TimeOfDay(hour: 8, minute: 0);
    _endTime = widget.schedule?.endTime ?? const TimeOfDay(hour: 20, minute: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.schedule == null
                  ? 'Добавить расписание'
                  : 'Редактировать расписание',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildTimePicker(
                    'Начало',
                    _startTime,
                    (val) => setState(() => _startTime = val),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTimePicker(
                    'Конец',
                    _endTime,
                    (val) => setState(() => _endTime = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: 16),
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                  child: const Text('Сохранить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePicker(
    String label,
    TimeOfDay time,
    ValueChanged<TimeOfDay> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.textGrey,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: time,
            );
            if (picked != null) onChanged(picked);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.access_time,
                  size: 20,
                  color: AppTheme.textDark,
                ),
                const SizedBox(width: 12),
                Text(
                  time.format(context),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _save() {
    final schedule =
        widget.schedule?.copyWith(startTime: _startTime, endTime: _endTime) ??
        LightingScheduleItem(
          id: const Uuid().v4(),
          startTime: _startTime,
          endTime: _endTime,
        );

    if (widget.schedule == null) {
      context.read<LightingBloc>().add(AddLightingSchedule(schedule));
    } else {
      context.read<LightingBloc>().add(UpdateLightingSchedule(schedule));
    }
    Navigator.pop(context);
  }
}
