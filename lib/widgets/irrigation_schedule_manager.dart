import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:uuid/uuid.dart';
import '../blocs/irrigation/irrigation_bloc.dart';
import '../blocs/irrigation/irrigation_event.dart';
import '../blocs/irrigation/irrigation_state.dart';
import '../models/irrigation_models.dart';
import '../theme/app_theme.dart';

class IrrigationScheduleManager extends StatelessWidget {
  final IrrigationMachine machine;

  const IrrigationScheduleManager({super.key, required this.machine});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<IrrigationBloc, IrrigationState>(
      builder: (context, state) {
        IrrigationMachine currentMachine = machine;
        if (state is IrrigationLoaded) {
          currentMachine = state.machines.firstWhere(
            (m) => m.id == machine.id,
            orElse: () => machine,
          );
        }

        return Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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
                      'Расписание: ${currentMachine.name}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: currentMachine.schedules.isEmpty
                      ? Center(
                          child: Text(
                            'Нет активных расписаний',
                            style: TextStyle(color: AppTheme.textGrey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: currentMachine.schedules.length,
                          itemBuilder: (context, index) {
                            final schedule = currentMachine.schedules[index];
                            return _buildScheduleItem(context, schedule);
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
                      backgroundColor: AppTheme.primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScheduleItem(
    BuildContext context,
    IrrigationScheduleItem schedule,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: schedule.isEnabled
              ? AppTheme.primaryGreen.withOpacity(0.3)
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
                    ? AppTheme.primaryGreen.withOpacity(0.1)
                    : Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                FontAwesomeIcons.clock,
                color: schedule.isEnabled ? AppTheme.primaryGreen : Colors.grey,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${schedule.startTime.format(context)} - ${schedule.endTime.format(context)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Пауза: ${schedule.pauseMinutes} мин',
                    style: const TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: schedule.isEnabled,
              activeColor: AppTheme.primaryGreen,
              onChanged: (value) {
                context.read<IrrigationBloc>().add(
                  UpdateSchedule(
                    machine.id,
                    schedule.copyWith(isEnabled: value),
                  ),
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
                context.read<IrrigationBloc>().add(
                  DeleteSchedule(machine.id, schedule.id),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(
    BuildContext context, {
    IrrigationScheduleItem? schedule,
  }) {
    showDialog(
      context: context,
      builder: (context) =>
          _ScheduleEditDialog(machineId: machine.id, schedule: schedule),
    );
  }
}

class _ScheduleEditDialog extends StatefulWidget {
  final String machineId;
  final IrrigationScheduleItem? schedule;

  const _ScheduleEditDialog({required this.machineId, this.schedule});

  @override
  State<_ScheduleEditDialog> createState() => _ScheduleEditDialogState();
}

class _ScheduleEditDialogState extends State<_ScheduleEditDialog> {
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late double _pauseMinutes;

  @override
  void initState() {
    super.initState();
    _startTime =
        widget.schedule?.startTime ?? const TimeOfDay(hour: 8, minute: 0);
    _endTime = widget.schedule?.endTime ?? const TimeOfDay(hour: 20, minute: 0);
    _pauseMinutes = widget.schedule?.pauseMinutes.toDouble() ?? 60.0;
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
            Text(
              'Интервал паузы: ${_pauseMinutes.round()} мин',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            Slider(
              value: _pauseMinutes,
              min: 1,
              max: 240,
              divisions: 239,
              activeColor: AppTheme.primaryGreen,
              label: '${_pauseMinutes.round()} мин',
              onChanged: (value) => setState(() => _pauseMinutes = value),
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
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                  ),
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
    ValueChanged<TimeOfDay> onPicked,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textGrey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: time,
            );
            if (picked != null) onPicked(picked);
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.access_time,
                  size: 16,
                  color: AppTheme.textGrey,
                ),
                const SizedBox(width: 8),
                Text(
                  time.format(context),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _save() {
    final schedule = IrrigationScheduleItem(
      id: widget.schedule?.id ?? const Uuid().v4(),
      startTime: _startTime,
      endTime: _endTime,
      pauseMinutes: _pauseMinutes.round(),
      isEnabled: widget.schedule?.isEnabled ?? true,
    );

    if (widget.schedule == null) {
      context.read<IrrigationBloc>().add(
        AddSchedule(widget.machineId, schedule),
      );
    } else {
      context.read<IrrigationBloc>().add(
        UpdateSchedule(widget.machineId, schedule),
      );
    }
    Navigator.pop(context);
  }
}
