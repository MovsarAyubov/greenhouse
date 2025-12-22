import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/irrigation/irrigation_bloc.dart';
import '../blocs/irrigation/irrigation_event.dart';
import '../models/irrigation_models.dart';
import '../theme/app_theme.dart';

class IrrigationSettingsDialog extends StatefulWidget {
  final IrrigationMachine machine;

  const IrrigationSettingsDialog({super.key, required this.machine});

  @override
  State<IrrigationSettingsDialog> createState() =>
      _IrrigationSettingsDialogState();
}

class _IrrigationSettingsDialogState extends State<IrrigationSettingsDialog> {
  late TextEditingController _pumpController;
  late TextEditingController _phController;
  late TextEditingController _ecController;
  late List<IrrigationBlock> _blocks;

  @override
  void initState() {
    super.initState();
    _pumpController = TextEditingController(
      text: widget.machine.pumpCapacity.toString(),
    );
    _phController = TextEditingController(
      text: widget.machine.targetPH.toString(),
    );
    _ecController = TextEditingController(
      text: widget.machine.targetEC.toString(),
    );
    _blocks = List.from(widget.machine.assignedBlocks);
  }

  @override
  void dispose() {
    _pumpController.dispose();
    _phController.dispose();
    _ecController.dispose();
    super.dispose();
  }

  void _save() {
    final newPump =
        double.tryParse(_pumpController.text) ?? widget.machine.pumpCapacity;
    final newPH =
        double.tryParse(_phController.text) ?? widget.machine.targetPH;
    final newEC =
        double.tryParse(_ecController.text) ?? widget.machine.targetEC;

    final updatedMachine = widget.machine.copyWith(
      pumpCapacity: newPump,
      targetPH: newPH,
      targetEC: newEC,
      assignedBlocks: _blocks,
    );

    // We need a new event for updating settings.
    // For now, we can assume the repository has a method or we add an event.
    // Let's add UpdateMachineSettings event to the Bloc later.
    context.read<IrrigationBloc>().add(UpdateMachineSettings(updatedMachine));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Настройки: ${widget.machine.name}',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('Общие настройки'),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            'Насос (Л/ч)',
                            _pumpController,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField('Целевой pH', _phController),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField('Целевой EC', _ecController),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Конфигурация блоков и клапанов'),
                    const SizedBox(height: 16),
                    ..._blocks.asMap().entries.map((entry) {
                      final blockIndex = entry.key;
                      final block = entry.value;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            block.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryGreen,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...block.valves.asMap().entries.map((valveEntry) {
                            final valveIndex = valveEntry.key;
                            final valve = valveEntry.value;
                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: 12.0,
                                left: 12.0,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(width: 80, child: Text(valve.name)),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildNumberInput(
                                      'Капельницы',
                                      valve.dripperCount.toString(),
                                      (val) {
                                        final count = int.tryParse(val);
                                        if (count != null) {
                                          setState(() {
                                            final newValves =
                                                List<IrrigationValve>.from(
                                                  block.valves,
                                                );
                                            newValves[valveIndex] = valve
                                                .copyWith(dripperCount: count);
                                            _blocks[blockIndex] = block
                                                .copyWith(valves: newValves);
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildNumberInput(
                                      'Объем/Кап. (Л)',
                                      valve.targetVolumePerDripper.toString(),
                                      (val) {
                                        final vol = double.tryParse(val);
                                        if (vol != null) {
                                          setState(() {
                                            final newValves =
                                                List<IrrigationValve>.from(
                                                  block.valves,
                                                );
                                            newValves[valveIndex] = valve
                                                .copyWith(
                                                  targetVolumePerDripper: vol,
                                                );
                                            _blocks[blockIndex] = block
                                                .copyWith(valves: newValves);
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const Divider(),
                        ],
                      );
                    }),
                  ],
                ),
              ),
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
                  child: const Text('Сохранить изменения'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppTheme.textDark,
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildNumberInput(
    String label,
    String initialValue,
    ValueChanged<String> onChanged,
  ) {
    return TextFormField(
      initialValue: initialValue,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onChanged: onChanged,
    );
  }
}
