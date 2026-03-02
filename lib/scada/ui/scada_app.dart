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
                          color: controller.connected
                              ? Colors.green
                              : Colors.red,
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
    final z = controller.zones.first;
    final w = controller.weather;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          Card(
            color: w.online ? Colors.white : Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Weather Station',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('State: ${w.online ? 'online' : 'offline'}'),
                  Text(
                    'Last update: ${w.lastUpdate?.toIso8601String() ?? '-'}',
                  ),
                  if (!w.online && w.lastError != null)
                    Text('Last error: ${w.lastError}'),
                  const SizedBox(height: 6),
                  _weatherRow(
                    label: 'OUT_TEMP',
                    valueText: _weatherDisplayValue(w, 0, 'C', 1),
                    quality: _weatherQuality(w, 0),
                    ageSec: _weatherAge(w, 0),
                    valid: _weatherUsable(w, 0),
                  ),
                  _weatherRow(
                    label: 'OUT_HUM',
                    valueText: _weatherDisplayValue(w, 1, '%RH', 1),
                    quality: _weatherQuality(w, 1),
                    ageSec: _weatherAge(w, 1),
                    valid: _weatherUsable(w, 1),
                  ),
                  _weatherRow(
                    label: 'WIND_SPEED',
                    valueText: _weatherDisplayValue(w, 2, 'm/s', 1),
                    quality: _weatherQuality(w, 2),
                    ageSec: _weatherAge(w, 2),
                    valid: _weatherUsable(w, 2),
                  ),
                  _weatherRow(
                    label: 'WIND_DIR',
                    valueText: _weatherDisplayValue(w, 3, 'deg', 0),
                    quality: _weatherQuality(w, 3),
                    ageSec: _weatherAge(w, 3),
                    valid: _weatherUsable(w, 3),
                  ),
                  _weatherRow(
                    label: 'RAIN_FLAG',
                    valueText: _weatherRainValueText(w, 4),
                    quality: _weatherQuality(w, 4),
                    ageSec: _weatherAge(w, 4),
                    valid: _weatherUsable(w, 4),
                  ),
                  _weatherRow(
                    label: 'SOLAR_RAD',
                    valueText: _weatherDisplayValue(w, 5, 'W/m2', 0),
                    quality: _weatherQuality(w, 5),
                    ageSec: _weatherAge(w, 5),
                    valid: _weatherUsable(w, 5),
                  ),
                  _weatherRow(
                    label: 'BARO_PRESS',
                    valueText: _weatherDisplayValue(w, 6, 'hPa', 1),
                    quality: _weatherQuality(w, 6),
                    ageSec: _weatherAge(w, 6),
                    valid: _weatherUsable(w, 6),
                  ),
                  _weatherRow(
                    label: 'DEW_POINT',
                    valueText: _weatherDisplayValue(w, 7, 'C', 1),
                    quality: _weatherQuality(w, 7),
                    ageSec: _weatherAge(w, 7),
                    valid: _weatherUsable(w, 7),
                  ),
                  _weatherRow(
                    label: 'STATUS_BITS',
                    valueText: _weatherStatusBitsText(w, 8),
                    quality: _weatherQuality(w, 8),
                    ageSec: _weatherAge(w, 8),
                    valid: _weatherUsable(w, 8),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
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
          ),
        ],
      ),
    );
  }

  Widget _weatherRow({
    required String label,
    required String valueText,
    required int quality,
    required int ageSec,
    required bool valid,
  }) {
    final color = !valid
        ? Colors.red
        : (quality == 0 ? Colors.black87 : Colors.orange.shade800);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        '$label: $valueText | ${_qualityLabel(quality)} | age:${ageSec}s',
        style: TextStyle(color: color),
      ),
    );
  }

  double? _weatherValue(WeatherStationState state, int index) {
    if (index < 0 || index >= state.values.length) {
      return null;
    }
    return state.values[index];
  }

  int _weatherQuality(WeatherStationState state, int index) {
    if (index < 0 || index >= state.qualityCodes.length) {
      return 3;
    }
    return state.qualityCodes[index];
  }

  int _weatherAge(WeatherStationState state, int index) {
    if (index < 0 || index >= state.ageSec.length) {
      return 0;
    }
    return state.ageSec[index];
  }

  bool _weatherUsable(WeatherStationState state, int index) {
    if (index < 0 || index >= state.flags.length) {
      return false;
    }
    final hasValidFlag = (state.flags[index] & 0x0001) != 0;
    return hasValidFlag && _weatherQuality(state, index) != 3;
  }

  String _formatValue(double? value, String unit, int decimals) {
    if (value == null) {
      return 'N/A';
    }
    return '${value.toStringAsFixed(decimals)} $unit';
  }

  String _weatherDisplayValue(
    WeatherStationState state,
    int index,
    String unit,
    int decimals,
  ) {
    if (!_weatherUsable(state, index)) {
      return 'N/A';
    }
    return _formatValue(_weatherValue(state, index), unit, decimals);
  }

  String _weatherRainValueText(WeatherStationState state, int index) {
    if (!_weatherUsable(state, index)) {
      return 'N/A';
    }
    final value = _weatherValue(state, index);
    if (value == null) {
      return 'N/A';
    }
    return ((value.round() & 0x1) == 1) ? '1' : '0';
  }

  String _weatherStatusBitsText(WeatherStationState state, int index) {
    if (!_weatherUsable(state, index)) {
      return 'N/A';
    }
    final value = _weatherValue(state, index);
    if (value == null) {
      return 'N/A';
    }
    final bits = value.round() & 0xFFFF;
    return '0x${bits.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  }

  String _qualityLabel(int quality) {
    switch (quality) {
      case 0:
        return 'OK';
      case 1:
        return 'STALE';
      case 2:
        return 'FAULT';
      case 3:
        return 'OFFLINE';
      default:
        return 'Q$quality';
    }
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
          const Text('Sensors (read only, Points float32 decode)'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List<Widget>.generate(zone.sensors.length, (i) {
              final quality = i < zone.sensorQualityCodes.length
                  ? zone.sensorQualityCodes[i]
                  : 3;
              final ageSec = i < zone.sensorAgeSec.length
                  ? zone.sensorAgeSec[i]
                  : 0;
              final flags = i < zone.sensorFlags.length
                  ? zone.sensorFlags[i]
                  : 0;
              final hasValidFlag = (flags & 0x0001) != 0;
              final usable = hasValidFlag && quality == 0;
              final valueText = usable
                  ? zone.sensors[i].toStringAsFixed(1)
                  : 'N/A';
              return Chip(
                label: Text(
                  '${c.config.sensorNames[i]}: $valueText | ${_qualityLabel(quality)} | age:${ageSec}s',
                ),
                backgroundColor: !hasValidFlag
                    ? Colors.red.shade100
                    : (quality != 0 ? Colors.grey.shade300 : null),
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
                  onChanged: (v) =>
                      _updateSetpoints(draft.setpoints.copyWith(setTemp: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  label: 'Set Hum',
                  value: draft.setpoints.setHum,
                  onChanged: (v) =>
                      _updateSetpoints(draft.setpoints.copyWith(setHum: v)),
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
                  onChanged: (v) =>
                      _updateSetpoints(draft.setpoints.copyWith(hystTemp: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  label: 'Hyst Hum',
                  value: draft.setpoints.hystHum,
                  onChanged: (v) =>
                      _updateSetpoints(draft.setpoints.copyWith(hystHum: v)),
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
                      await c.applyCommand(
                        zoneId: zone.zoneId,
                        draft: currentDraft,
                      );
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

  String _qualityLabel(int quality) {
    switch (quality) {
      case 0:
        return 'OK';
      case 1:
        return 'STALE';
      case 2:
        return 'FAULT';
      case 3:
        return 'OFFLINE';
      default:
        return 'Q$quality';
    }
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
  const _TrendChart({required this.points, required this.selectedSensors});

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
      final sensorPoints =
          points
              .where((p) => p.sensorIndex == sensor)
              .map(
                (p) =>
                    FlSpot(p.time.millisecondsSinceEpoch.toDouble(), p.value),
              )
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
            decoration: const InputDecoration(
              labelText: 'Stale threshold, sec',
            ),
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
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Client trace (latest 120 lines)'),
              const Spacer(),
              TextButton(
                onPressed: () {
                  widget.controller.clearClientTrace();
                  setState(() => _status = 'Client trace cleared');
                },
                child: const Text('Clear trace'),
              ),
            ],
          ),
          Container(
            constraints: const BoxConstraints(minHeight: 140, maxHeight: 280),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                widget.controller.clientTrace.take(120).join('\n'),
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text('File: logs/client_trace.csv'),
        ],
      ),
    );
  }
}
