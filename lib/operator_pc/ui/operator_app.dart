import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/operator_models.dart';
import '../services/app_controller.dart';

class OperatorApp extends StatefulWidget {
  const OperatorApp({super.key});

  @override
  State<OperatorApp> createState() => _OperatorAppState();
}

class _OperatorAppState extends State<OperatorApp> {
  late final AppController controller;

  @override
  void initState() {
    super.initState();
    controller = AppController(host: '192.168.50.20', port: 5000);
    unawaited(controller.init());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Greenhouse Operator',
      home: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return DefaultTabController(
            length: 5,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Greenhouse Operator PC'),
                bottom: const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Dashboard'),
                    Tab(text: 'Sensors'),
                    Tab(text: 'Setpoints'),
                    Tab(text: 'Events'),
                    Tab(text: 'Logs/Export'),
                  ],
                ),
              ),
              body: TabBarView(
                children: [
                  _DashboardTab(controller: controller),
                  _SensorsTab(controller: controller),
                  _SetpointsTab(controller: controller),
                  _EventsTab(controller: controller),
                  _LogsTab(controller: controller),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.status;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Connection: ${s.connected ? 'Connected' : 'Disconnected'}'),
          Text('RTT: ${s.rttMs} ms'),
          Text('Active config: v${s.activeConfigVersion}'),
          Text('Last error code: ${s.lastErrorCode}'),
          Text(
            'Last telemetry: ${s.lastSnapshotAt == null ? '-' : DateFormat('yyyy-MM-dd HH:mm:ss').format(s.lastSnapshotAt!)}',
          ),
          const SizedBox(height: 12),
          Text('Events in memory: ${controller.events.length}'),
        ],
      ),
    );
  }
}

class _SensorsTab extends StatefulWidget {
  const _SensorsTab({required this.controller});

  final AppController controller;

  @override
  State<_SensorsTab> createState() => _SensorsTabState();
}

class _SensorsTabState extends State<_SensorsTab> {
  SensorQuality? qualityFilter;

  @override
  Widget build(BuildContext context) {
    var items = widget.controller.sensors;
    if (qualityFilter != null) {
      items = items.where((s) => s.quality == qualityFilter).toList();
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              const Text('Filter by quality: '),
              const SizedBox(width: 8),
              DropdownButton<SensorQuality?>(
                value: qualityFilter,
                items: [
                  const DropdownMenuItem<SensorQuality?>(value: null, child: Text('All')),
                  ...SensorQuality.values.map(
                    (q) => DropdownMenuItem<SensorQuality?>(
                      value: q,
                      child: Text(q.name.toUpperCase()),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => qualityFilter = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final s = items[i];
                return ListTile(
                  dense: true,
                  title: Text('Sensor ${s.id.toString().padLeft(3, '0')}'),
                  subtitle: Text('q=${s.quality.name.toUpperCase()}  t=${DateFormat('HH:mm:ss').format(s.timestamp)}'),
                  trailing: Text(s.value.toStringAsFixed(2)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SetpointsTab extends StatefulWidget {
  const _SetpointsTab({required this.controller});

  final AppController controller;

  @override
  State<_SetpointsTab> createState() => _SetpointsTabState();
}

class _SetpointsTabState extends State<_SetpointsTab> {
  final TextEditingController _versionCtrl = TextEditingController(text: '1');
  final TextEditingController _userCtrl = TextEditingController(text: 'operator');
  final TextEditingController _payloadCtrl = TextEditingController(
    text: '24.5,70.0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0',
  );

  @override
  void dispose() {
    _versionCtrl.dispose();
    _userCtrl.dispose();
    _payloadCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Text('Active version on master: v${c.status.activeConfigVersion}'),
          const SizedBox(height: 8),
          Text('Current config[0..3]: ${c.currentConfig.take(4).map((v) => v.toStringAsFixed(2)).join(', ')}'),
          const SizedBox(height: 8),
          Text('Apply status: ${c.setpointStatus}'),
          const SizedBox(height: 12),
          TextField(
            controller: _versionCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'New config version'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _userCtrl,
            decoration: const InputDecoration(labelText: 'User'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _payloadCtrl,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: '32 float32 values (comma/space/newline separated)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: c.setpointBusy
                ? null
                : () async {
                    final v = int.tryParse(_versionCtrl.text.trim()) ?? 0;
                    List<double> values;
                    try {
                      values = _parseFloatList(_payloadCtrl.text);
                      if (values.length != 32) {
                        throw const FormatException('Expected exactly 32 values');
                      }
                    } catch (_) {
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Invalid payload, expected 32 float values')),
                      );
                      return;
                    }
                    await c.sendSetpoints(
                      newVersion: v,
                      values: values,
                      user: _userCtrl.text.trim(),
                    );
                  },
            child: const Text('Send SETPOINTS_PUT + APPLY'),
          ),
        ],
      ),
    );
  }

  List<double> _parseFloatList(String text) {
    final tokens = text
        .split(RegExp(r'[\s,;]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    return tokens.map(double.parse).toList();
  }
}

class _EventsTab extends StatefulWidget {
  const _EventsTab({required this.controller});

  final AppController controller;

  @override
  State<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<_EventsTab> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchCtrl.text.trim();
    final events = widget.controller.events.where((e) {
      if (q.isEmpty) {
        return true;
      }
      return e.code.toString().contains(q) ||
          e.source.toString().contains(q) ||
          e.eventId.toString().contains(q) ||
          e.severity.name.contains(q.toLowerCase());
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              labelText: 'Search by severity/code/source/event_id',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: events.length,
              itemBuilder: (context, i) {
                final e = events[i];
                return Card(
                  child: ListTile(
                    title: Text('#${e.eventId} ${e.severity.name.toUpperCase()} code=${e.code} source=${e.source}'),
                    subtitle: Text(DateFormat('yyyy-MM-dd HH:mm:ss').format(e.timestamp)),
                    trailing: Text(e.value.toStringAsFixed(2)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LogsTab extends StatefulWidget {
  const _LogsTab({required this.controller});

  final AppController controller;

  @override
  State<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<_LogsTab> {
  DateTime from = DateTime.now().subtract(const Duration(days: 1));
  DateTime to = DateTime.now();
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('From: ${DateFormat('yyyy-MM-dd').format(from)}'),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    initialDate: from,
                  );
                  if (d != null) {
                    setState(() => from = d);
                  }
                },
                child: const Text('Pick'),
              ),
              const SizedBox(width: 16),
              Text('To: ${DateFormat('yyyy-MM-dd').format(to)}'),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    initialDate: to,
                  );
                  if (d != null) {
                    setState(() => to = d);
                  }
                },
                child: const Text('Pick'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        await widget.controller.exportCsv(from, to);
                        if (mounted) {
                          setState(() => busy = false);
                        }
                      },
                child: const Text('Export CSV'),
              ),
              ElevatedButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        await widget.controller.exportXlsx(from, to);
                        if (mounted) {
                          setState(() => busy = false);
                        }
                      },
                child: const Text('Export XLSX'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Last export: ${widget.controller.lastExportPath ?? '-'}'),
        ],
      ),
    );
  }
}
