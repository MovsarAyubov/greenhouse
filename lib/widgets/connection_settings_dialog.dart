import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../theme/app_theme.dart';

class ConnectionSettingsDialog extends StatefulWidget {
  const ConnectionSettingsDialog({super.key});

  @override
  State<ConnectionSettingsDialog> createState() =>
      _ConnectionSettingsDialogState();
}

class _ConnectionSettingsDialogState extends State<ConnectionSettingsDialog> {
  List<String> _availablePorts = [];
  String? _selectedPort;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPorts();
  }

  Future<void> _loadPorts() async {
    setState(() => _isLoading = true);
    try {
      // Get available ports
      _availablePorts = SerialPort.availablePorts;
    } catch (e) {
      print('Error loading ports: $e');
    } finally {
      setState(() => _isLoading = false);
    }
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Настройки подключения',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadPorts,
                  tooltip: 'Обновить список портов',
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_availablePorts.isEmpty)
              Center(
                child: Text(
                  'Нет доступных COM-портов',
                  style: TextStyle(color: AppTheme.textGrey),
                ),
              )
            else
              DropdownButtonFormField<String>(
                value: _selectedPort,
                decoration: InputDecoration(
                  labelText: 'Выберите COM-порт',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: _availablePorts.map((port) {
                  return DropdownMenuItem(value: port, child: Text(port));
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedPort = value);
                },
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
                  onPressed: _selectedPort == null
                      ? null
                      : () {
                          // TODO: Save port and connect
                          Navigator.pop(context, _selectedPort);
                        },
                  style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                  child: const Text('Подключить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
