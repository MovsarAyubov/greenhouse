import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/scada_models.dart';
import '../services/scada_controller.dart';

class ScadaApp extends StatefulWidget {
  const ScadaApp({super.key});

  @override
  State<ScadaApp> createState() => _ScadaAppState();
}

class _ScadaAppState extends State<ScadaApp> {
  late final ScadaController controller;

  @override
  void initState() {
    super.initState();
    controller = ScadaController();
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
      title: 'Greenhouse SCADA',
      home: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return DefaultTabController(
            length: 4,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Greenhouse SCADA'),
                bottom: const TabBar(
                  tabs: [
                    Tab(text: 'Dashboard'),
                    Tab(text: 'Zone'),
                    Tab(text: 'Alarms'),
                    Tab(text: 'Settings'),
                  ],
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: Text(
                        controller.connected ? 'CONNECTED' : 'DISCONNECTED',
                        style: TextStyle(
                          color: controller.connected ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              body: TabBarView(
                children: [
                  _DashboardTab(controller: controller),
                  _ZoneTab(controller: controller),
                  _AlarmsTab(controller: controller),
                  _SettingsTab(controller: controller),
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

  final ScadaController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        itemCount: controller.zones.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 1.8,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemBuilder: (context, i) {
          final z = controller.zones[i];
          return Card(
            color: z.online ? Colors.white : Colors.red.shade50,
            child: InkWell(
              onTap: () {
                controller.selectZone(z.zoneId);
                DefaultTabController.of(context).animateTo(1);
              },
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zone ${z.zoneId}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('T: ${z.temperature.toStringAsFixed(1)} C'),
                    Text('H: ${z.humidity.toStringAsFixed(1)} %'),
                    Text('Online: ${z.online ? 'yes' : 'no'}'),
                    Text('Stale: ${z.stale ? 'yes' : 'no'}'),
                    Text('Out ON: ${z.outputs.where((o) => o).length}/16'),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ZoneTab extends StatefulWidget {
  const _ZoneTab({required this.controller});

  final ScadaController controller;

  @override
  State<_ZoneTab> createState() => _ZoneTabState();
}

class _ZoneTabState extends State<_ZoneTab> {
  ZoneCommandDraft? _draft;
  int? _draftZoneId;
  final Set<int> _trendSensors = <int>{0};
  String _applyStatus = '';

  @override
  void didUpdateWidget(covariant _ZoneTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDraft();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final zone = c.selectedZone;
    _syncDraft();
    final draft = _draft!;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List<Widget>.generate(c.zones.length, (i) {
              final z = i + 1;
              return ChoiceChip(
                label: Text('Zone $z'),
                selected: z == c.selectedZoneId,
                onSelected: (_) => c.selectZone(z),
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(
            'Mode: ${zone.mode.name.toUpperCase()} | Online: ${zone.online ? 'yes' : 'no'} | '
            'Stale: ${zone.stale ? 'yes' : 'no'} | Poll: ${zone.lastPollMs}ms | '
            'Age: ${zone.lastOkAgeSec}s',
          ),
          const SizedBox(height: 10),
          Text(
            'Errors timeout/crc/exception: '
            '${zone.errTimeout}/${zone.errCrc}/${zone.errException} | '
            'Data version: ${zone.dataVersion} | Last applied: ${zone.lastAppliedTrigger}',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: ZoneMode.values.map((mode) {
              return ChoiceChip(
                label: Text(mode.name.toUpperCase()),
                selected: draft.mode == mode,
                onSelected: (_) => setState(() {
                  _draft = ZoneCommandDraft(
                    mode: mode,
                    setpoints: draft.setpoints,
                    outputsManual: draft.outputsManual,
                  );
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          const Text('Sensors (read only, x10 scaling applied)'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List<Widget>.generate(zone.sensors.length, (i) {
              final valid = (zone.sensorValidMask & (1 << i)) != 0;
              return Chip(
                label: Text(
                  '${c.config.sensorNames[i]}: ${zone.sensors[i].toStringAsFixed(1)}',
                ),
                backgroundColor: valid ? null : Colors.red.shade100,
              );
            }),
          ),
          const SizedBox(height: 8),
          const Text('Setpoints'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: 'Set Temp',
                  value: draft.setpoints.setTemp,
                  onChanged: (v) => _updateSetpoints(
                    draft.setpoints.copyWith(setTemp: v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  label: 'Set Hum',
                  value: draft.setpoints.setHum,
                  onChanged: (v) => _updateSetpoints(
                    draft.setpoints.copyWith(setHum: v),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: 'Hyst Temp',
                  value: draft.setpoints.hystTemp,
                  onChanged: (v) => _updateSetpoints(
                    draft.setpoints.copyWith(hystTemp: v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  label: 'Hyst Hum',
                  value: draft.setpoints.hystHum,
                  onChanged: (v) => _updateSetpoints(
                    draft.setpoints.copyWith(hystHum: v),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: 'Min ON sec',
                  value: draft.setpoints.minOnSec.toDouble(),
                  decimals: 0,
                  onChanged: (v) => _updateSetpoints(
                    draft.setpoints.copyWith(minOnSec: v.round()),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  label: 'Min OFF sec',
                  value: draft.setpoints.minOffSec.toDouble(),
                  decimals: 0,
                  onChanged: (v) => _updateSetpoints(
                    draft.setpoints.copyWith(minOffSec: v.round()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Manual outputs'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List<Widget>.generate(16, (i) {
              final enabled = draft.mode == ZoneMode.manual;
              return FilterChip(
                label: Text(c.config.outputNames[i]),
                selected: draft.outputsManual[i],
                onSelected: enabled
                    ? (v) {
                        setState(() {
                          final values = List<bool>.from(draft.outputsManual);
                          values[i] = v;
                          _draft = ZoneCommandDraft(
                            mode: draft.mode,
                            setpoints: draft.setpoints,
                            outputsManual: values,
                          );
                        });
                      }
                    : null,
              );
            }),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: zone.online
                ? () async {
                    final currentDraft = _draft!;
                    setState(() => _applyStatus = 'Applying...');
                    try {
                      await c.applyCommand(zoneId: zone.zoneId, draft: currentDraft);
                      if (mounted) {
                        setState(() => _applyStatus = 'Applied');
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() => _applyStatus = 'Failed: $e');
                      }
                    }
                  }
                : null,
            child: const Text('Apply'),
          ),
          const SizedBox(height: 6),
          Text(_applyStatus),
          const Divider(height: 28),
          const Text('Trend (select 1-3 sensors)'),
          Wrap(
            spacing: 8,
            children: List<Widget>.generate(9, (i) {
              final selected = _trendSensors.contains(i);
              return FilterChip(
                label: Text(c.config.sensorNames[i]),
                selected: selected,
                onSelected: (v) {
                  setState(() {
                    if (v && _trendSensors.length < 3) {
                      _trendSensors.add(i);
                    } else if (!v) {
                      _trendSensors.remove(i);
                    }
                    if (_trendSensors.isEmpty) {
                      _trendSensors.add(0);
                    }
                  });
                },
              );
            }),
          ),
          SizedBox(
            height: 240,
            child: _TrendChart(
              points: c.trendPoints(
                zoneId: zone.zoneId,
                sensors: _trendSensors,
                window: const Duration(hours: 1),
              ),
              selectedSensors: _trendSensors,
            ),
          ),
        ],
      ),
    );
  }

  void _syncDraft() {
    final zone = widget.controller.selectedZone;
    if (_draft == null ||
        _draftZoneId != zone.zoneId ||
        _draft!.outputsManual.length != zone.outputs.length) {
      _draft = ZoneCommandDraft.fromZone(zone);
      _draftZoneId = zone.zoneId;
    }
  }

  void _updateSetpoints(ZoneSetpoints setpoints) {
    final draft = _draft!;
    setState(() {
      _draft = ZoneCommandDraft(
        mode: draft.mode,
        setpoints: setpoints,
        outputsManual: draft.outputsManual,
      );
    });
  }
}

class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.decimals = 1,
  });

  final String label;
  final double value;
  final int decimals;
  final ValueChanged<double> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value.toStringAsFixed(widget.decimals),
    );
  }

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value.toStringAsFixed(widget.decimals);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: widget.label),
      onChanged: (value) {
        final parsed = double.tryParse(value.replaceAll(',', '.'));
        if (parsed != null) {
          widget.onChanged(parsed);
        }
      },
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({
    required this.points,
    required this.selectedSensors,
  });

  final List<TrendPoint> points;
  final Set<int> selectedSensors;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(child: Text('No trend data yet'));
    }

    final colors = <Color>[Colors.blue, Colors.green, Colors.orange];
    final sensors = selectedSensors.toList()..sort();
    final minTime = points
        .map((e) => e.time.millisecondsSinceEpoch.toDouble())
        .reduce((a, b) => a < b ? a : b);
    final maxTime = points
        .map((e) => e.time.millisecondsSinceEpoch.toDouble())
        .reduce((a, b) => a > b ? a : b);

    final lines = <LineChartBarData>[];
    for (var i = 0; i < sensors.length; i++) {
      final sensor = sensors[i];
      final sensorPoints = points
          .where((p) => p.sensorIndex == sensor)
          .map((p) => FlSpot(p.time.millisecondsSinceEpoch.toDouble(), p.value))
          .toList()
        ..sort((a, b) => a.x.compareTo(b.x));
      lines.add(
        LineChartBarData(
          spots: sensorPoints,
          isCurved: false,
          color: colors[i % colors.length],
          dotData: const FlDotData(show: false),
        ),
      );
    }

    return LineChart(
      LineChartData(
        minX: minTime,
        maxX: maxTime,
        lineBarsData: lines,
        titlesData: const FlTitlesData(show: false),
        gridData: const FlGridData(show: true),
      ),
    );
  }
}

class _AlarmsTab extends StatelessWidget {
  const _AlarmsTab({required this.controller});

  final ScadaController controller;

  @override
  Widget build(BuildContext context) {
    final active = controller.activeAlarms;
    final history = controller.alarmHistory;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Active alarms',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: active.length,
                    itemBuilder: (context, i) {
                      final a = active[i];
                      return Card(
                        child: ListTile(
                          title: Text('Zone ${a.zoneId}: ${a.type.name}'),
                          subtitle: Text(a.message),
                          trailing: TextButton(
                            onPressed: () => controller.ackAlarm(a.id),
                            child: Text(a.acknowledged ? 'Acked' : 'Ack'),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Alarm journal',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: history.length,
                    itemBuilder: (context, i) {
                      final a = history[i];
                      return ListTile(
                        dense: true,
                        title: Text('Zone ${a.zoneId} ${a.type.name}'),
                        subtitle: Text(
                          '${a.message}\nraised=${a.raisedAt.toIso8601String()}'
                          '${a.clearedAt == null ? '' : ' cleared=${a.clearedAt!.toIso8601String()}'}',
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.controller});

  final ScadaController controller;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  late final TextEditingController _ipCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _pollCtrl;
  late final TextEditingController _staleCtrl;
  late final TextEditingController _logCtrl;
  String _status = '';

  @override
  void initState() {
    super.initState();
    final c = widget.controller.config;
    _ipCtrl = TextEditingController(text: c.masterIp);
    _portCtrl = TextEditingController(text: '${c.masterPort}');
    _pollCtrl = TextEditingController(text: '${c.pollPeriodMs}');
    _staleCtrl = TextEditingController(text: '${c.staleThresholdSec}');
    _logCtrl = TextEditingController(text: '${c.logPeriodSec}');
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _pollCtrl.dispose();
    _staleCtrl.dispose();
    _logCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          TextField(
            controller: _ipCtrl,
            decoration: const InputDecoration(labelText: 'Master IP'),
          ),
          TextField(
            controller: _portCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Port'),
          ),
          TextField(
            controller: _pollCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Poll period, ms'),
          ),
          TextField(
            controller: _staleCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Stale threshold, sec'),
          ),
          TextField(
            controller: _logCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Log period, sec'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () async {
              final prev = widget.controller.config;
              final next = prev.copyWith(
                masterIp: _ipCtrl.text.trim(),
                masterPort: int.tryParse(_portCtrl.text) ?? prev.masterPort,
                pollPeriodMs: int.tryParse(_pollCtrl.text) ?? prev.pollPeriodMs,
                staleThresholdSec:
                    int.tryParse(_staleCtrl.text) ?? prev.staleThresholdSec,
                logPeriodSec: int.tryParse(_logCtrl.text) ?? prev.logPeriodSec,
              );
              await widget.controller.saveConfig(next);
              if (mounted) {
                setState(() => _status = 'Saved');
              }
            },
            child: const Text('Save settings'),
          ),
          const SizedBox(height: 8),
          Text(_status),
          if (widget.controller.lastError != null)
            Text('Last error: ${widget.controller.lastError}'),
          const SizedBox(height: 8),
          const Text('Register map is configured for current server spec.'),
        ],
      ),
    );
  }
}
