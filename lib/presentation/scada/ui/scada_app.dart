import 'dart:async';

import 'package:flutter/material.dart';

import 'package:greenhouse/domain/entities/scada/scada_models.dart';
import 'package:greenhouse/presentation/scada/controllers/scada_controller.dart';

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
          final tabs = <_TabEntry>[
            _TabEntry(
              label: 'Dashboard',
              child: _DashboardTab(controller: controller),
            ),
            ...controller.zoneModules.map(
              (module) => _TabEntry(
                label: 'Zone ${module.zoneId}',
                child: _ZoneModuleTab(controller: controller, module: module),
              ),
            ),
            if (controller.weatherModules.isNotEmpty)
              _TabEntry(
                label: 'Weather',
                child: _WeatherTab(controller: controller),
              ),
            _TabEntry(
              label: 'Settings',
              child: _SettingsTab(controller: controller),
            ),
          ];
          return DefaultTabController(
            length: tabs.length,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Greenhouse SCADA'),
                bottom: TabBar(
                  isScrollable: true,
                  tabs: tabs.map((tab) => Tab(text: tab.label)).toList(),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: Text(
                        controller.connected ? 'CONNECTED' : 'DISCONNECTED',
                      ),
                    ),
                  ),
                ],
              ),
              body: TabBarView(
                children: tabs.map((tab) => tab.child).toList(growable: false),
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
    final metadata = controller.deviceTopologyMetadata;
    final store = controller.topologySnapshot;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoCard(
          title: 'Session',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('State: ${controller.compatibility.state.name}'),
              Text(controller.compatibility.message),
              if (controller.lastError != null)
                Text('Last error: ${controller.lastError}'),
              Text('RTC: ${controller.serverRtcText}'),
            ],
          ),
        ),
        _InfoCard(
          title: 'Device topology',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Active: ${metadata?.isActive == true ? 'yes' : 'no'}'),
              Text(
                'Version: ${metadata == null ? '-' : '${metadata.versionMajor}.${metadata.versionMinor}'}',
              ),
              Text('Generation: ${metadata?.activeGeneration ?? '-'}'),
              Text('Size: ${metadata?.activeSizeBytes ?? '-'} bytes'),
            ],
          ),
        ),
        _InfoCard(
          title: 'Local topology',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Manifest: ${store.hasManifest ? 'loaded' : 'missing'}'),
              if (store.manifest != null)
                Text(
                  'schema=${store.manifest!.schemaVersion} generation=${store.manifest!.generation}',
                ),
              if (store.manifestError != null)
                Text('Manifest error: ${store.manifestError}'),
              Text(
                'Semantic catalog: ${store.hasSemanticCatalog ? 'loaded' : 'missing'}',
              ),
              if (store.semanticCatalogPath != null)
                Text('Semantic path: ${store.semanticCatalogPath}'),
              if (store.semanticCatalogError != null)
                Text('Semantic error: ${store.semanticCatalogError}'),
              Text('Blob: ${store.hasBlob ? 'loaded' : 'missing'}'),
              if (store.blobCrc32 != null)
                Text(
                  'Blob CRC32: 0x${store.blobCrc32!.toRadixString(16).toUpperCase()}',
                ),
              if (store.blobError != null)
                Text('Blob error: ${store.blobError}'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _InfoCard(
          title: 'Topology inventory',
          child: Column(
            children: controller.moduleSummaries
                .map(
                  (summary) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(summary.module.title),
                    subtitle: Text(
                      'module_id=${summary.module.moduleId}, slave=${summary.module.slaveId}, '
                      'points=${summary.pointCount}, schedule=${summary.scheduleAvailable ? 'yes' : 'no'}',
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _ZoneModuleTab extends StatelessWidget {
  const _ZoneModuleTab({required this.controller, required this.module});

  final ScadaController controller;
  final TopologyModule module;

  @override
  Widget build(BuildContext context) {
    final status = controller.slaveStatusForModule(module.moduleId);
    final points = controller.resolvedPointsForModule(module.moduleId);
    final lightingFeedback = controller.lightingFeedbackFieldsForModule(
      module.moduleId,
    );
    final scheduleStatus = controller.lightingStatusForModule(module.moduleId);
    final disabledReason = controller.scheduleDisabledReasonForModule(
      module.moduleId,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoCard(
          title: module.title,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('module_id=${module.moduleId}, slave_id=${module.slaveId}'),
              Text(
                'zone_id=${module.zoneId}, capability=0x${module.capabilityMask.toRadixString(16)}',
              ),
              Text(
                'online=${status?.online == true ? 'yes' : 'no'} stale=${status?.stale == true ? 'yes' : 'no'}',
              ),
              if (status != null)
                Text(
                  'age=${status.lastOkAgeSec}s timeout/crc/exc=${status.errTimeout}/${status.errCrc}/${status.errException}',
                ),
            ],
          ),
        ),
        _LightingFeedbackCard(fields: lightingFeedback),
        _InfoCard(
          title: 'Telemetry',
          child: Column(
            children: points
                .map(
                  (item) => ListTile(
                    dense: true,
                    title: Text(item.point.displayName),
                    subtitle: Text(
                      'publish_index=${item.point.publishIndex} quality=${item.telemetry?.quality ?? '-'} age=${item.telemetry?.ageSec ?? '-'}s',
                    ),
                    trailing: Text(
                      _formatPointValue(item.point, item.telemetry),
                      style: TextStyle(
                        color: item.telemetry?.isUsable == true
                            ? null
                            : Colors.grey,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        _ScheduleCard(
          controller: controller,
          module: module,
          status: scheduleStatus,
          disabledReason: disabledReason,
        ),
      ],
    );
  }
}

class _WeatherTab extends StatelessWidget {
  const _WeatherTab({required this.controller});

  final ScadaController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: controller.weatherModules
          .map(
            (module) => _InfoCard(
              title: module.title,
              child: Column(
                children: controller
                    .weatherFieldsForModule(module.moduleId)
                    .map(
                      (field) => ListTile(
                        dense: true,
                        title: Text(field.label),
                        subtitle: Text(field.message),
                        trailing: Text(
                          _formatSemanticField(field),
                          style: TextStyle(
                            color:
                                field.state ==
                                    ScadaCompatibilityState.pointContractMissing
                                ? Colors.grey
                                : null,
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _LightingFeedbackCard extends StatelessWidget {
  const _LightingFeedbackCard({required this.fields});

  final List<SemanticFieldView> fields;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Lighting feedback',
      child: Column(
        children: fields
            .map(
              (field) => ListTile(
                dense: true,
                title: Text(field.label),
                subtitle: Text(_lightingFeedbackSubtitle(field)),
                trailing: Text(
                  _formatLightingFeedbackField(field),
                  style: TextStyle(
                    color:
                        field.point == null ||
                            field.telemetry?.hasValidFlag != true
                        ? Colors.grey
                        : null,
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.controller,
    required this.module,
    required this.status,
    required this.disabledReason,
  });

  final ScadaController controller;
  final TopologyModule module;
  final LightingScheduleStatus status;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final draft = status.draft;
    return _InfoCard(
      title: 'Lighting setpoints',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRelaySection(
            context,
            title: 'Relay 1',
            relay: draft.relay1,
            onChanged: (relay) => controller.updateLightingDraft(
              module.moduleId,
              (current) => current.copyWith(relay1: relay),
            ),
          ),
          const SizedBox(height: 8),
          _buildRelaySection(
            context,
            title: 'Relay 2',
            relay: draft.relay2,
            onChanged: (relay) => controller.updateLightingDraft(
              module.moduleId,
              (current) => current.copyWith(relay2: relay),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: '${draft.hysteresisSec}',
            decoration: const InputDecoration(
              labelText: 'Hysteresis',
              suffixText: 's',
            ),
            enabled: disabledReason == null,
            keyboardType: TextInputType.number,
            onChanged: (value) => _updateIntField(
              value,
              (parsed) => controller.updateLightingDraft(
                module.moduleId,
                (current) => current.copyWith(hysteresisSec: parsed),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Recommended mode: full 13-word payload write'),
          if (disabledReason != null)
            Text(disabledReason!, style: const TextStyle(color: Colors.orange)),
          ElevatedButton(
            onPressed: disabledReason == null
                ? () => unawaited(
                    controller.sendScheduleForModule(module.moduleId),
                  )
                : null,
            child: const Text('Send setpoints'),
          ),
          const SizedBox(height: 6),
          Text(
            'phase=${status.phase.name} trigger=${status.trigger} '
            'applied=${status.lastAppliedTrigger} '
            'result=${status.lastResult}/${status.lastIoErr}',
          ),
          if (status.message != null) Text(status.message!),
        ],
      ),
    );
  }

  Future<void> _pickTime(
    BuildContext context,
    int hhmm,
    ValueChanged<int> onPicked,
  ) async {
    final initial = TimeOfDay(hour: hhmm ~/ 100, minute: hhmm % 100);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      onPicked(picked.hour * 100 + picked.minute);
    }
  }

  Widget _buildRelaySection(
    BuildContext context, {
    required String title,
    required LightingRelayDraft relay,
    required ValueChanged<LightingRelayDraft> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          value: relay.enabled,
          onChanged: disabledReason == null
              ? (value) => onChanged(relay.copyWith(enabled: value))
              : null,
        ),
        Row(
          children: [
            TextButton(
              onPressed: disabledReason == null
                  ? () => _pickTime(
                      context,
                      relay.onHhmm,
                      (value) => onChanged(relay.copyWith(onHhmm: value)),
                    )
                  : null,
              child: Text('ON ${_formatHhmm(relay.onHhmm)}'),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: disabledReason == null
                  ? () => _pickTime(
                      context,
                      relay.offHhmm,
                      (value) => onChanged(relay.copyWith(offHhmm: value)),
                    )
                  : null,
              child: Text('OFF ${_formatHhmm(relay.offHhmm)}'),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: '${relay.thresholdWm2}',
                decoration: const InputDecoration(
                  labelText: 'Threshold',
                  suffixText: 'W/m²',
                ),
                enabled: disabledReason == null,
                keyboardType: TextInputType.number,
                onChanged: (value) => _updateIntField(
                  value,
                  (parsed) => onChanged(relay.copyWith(thresholdWm2: parsed)),
                ),
              ),
            ),
          ],
        ),
        TextFormField(
          initialValue: '${relay.dliLimit}',
          decoration: const InputDecoration(labelText: 'DLI limit'),
          enabled: disabledReason == null,
          keyboardType: TextInputType.number,
          onChanged: (value) => _updateIntField(
            value,
            (parsed) => onChanged(relay.copyWith(dliLimit: parsed)),
          ),
        ),
      ],
    );
  }

  void _updateIntField(String value, ValueChanged<int> onParsed) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) {
      onParsed(parsed);
    }
  }
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.controller});

  final ScadaController controller;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _unitIdCtrl;
  late final TextEditingController _manifestCtrl;
  late final TextEditingController _blobCtrl;
  late final TextEditingController _semanticCtrl;
  late final TextEditingController _pollCtrl;
  late final TextEditingController _diagPollCtrl;
  late final TextEditingController _responseTimeoutCtrl;
  late final TextEditingController _retryCountCtrl;
  late final TextEditingController _retryBackoffCtrl;
  late final TextEditingController _rtcHourCtrl;
  late final TextEditingController _rtcMinuteCtrl;
  ModbusAddressMode _addressMode = ModbusAddressMode.zeroBased;
  bool _pausePollingDuringWrites = true;
  String _status = '';

  @override
  void initState() {
    super.initState();
    final config = widget.controller.config;
    _hostCtrl = TextEditingController(text: config.deviceConnection.host);
    _portCtrl = TextEditingController(text: '${config.deviceConnection.port}');
    _unitIdCtrl = TextEditingController(
      text: '${config.deviceConnection.unitId}',
    );
    _manifestCtrl = TextEditingController(
      text: config.localTopologyManifestPath,
    );
    _blobCtrl = TextEditingController(text: config.localTopologyBlobPath);
    _semanticCtrl = TextEditingController(text: config.semanticCatalogPath);
    _pollCtrl = TextEditingController(
      text: '${config.pollIntervals.telemetryMs}',
    );
    _diagPollCtrl = TextEditingController(
      text: '${config.pollIntervals.diagMs}',
    );
    _responseTimeoutCtrl = TextEditingController(
      text: '${config.timeouts.responseMs}',
    );
    _retryCountCtrl = TextEditingController(
      text: '${config.transport.retryCount}',
    );
    _retryBackoffCtrl = TextEditingController(
      text: '${config.timeouts.retryBackoffMs}',
    );
    _rtcHourCtrl = TextEditingController(
      text: '${widget.controller.serverRtcHour ?? 0}',
    );
    _rtcMinuteCtrl = TextEditingController(
      text: '${widget.controller.serverRtcMinute ?? 0}',
    );
    _addressMode = config.addressMode;
    _pausePollingDuringWrites =
        config.featureFlags.pausePollingDuringWriteWorkflows;
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _unitIdCtrl.dispose();
    _manifestCtrl.dispose();
    _blobCtrl.dispose();
    _semanticCtrl.dispose();
    _pollCtrl.dispose();
    _diagPollCtrl.dispose();
    _responseTimeoutCtrl.dispose();
    _retryCountCtrl.dispose();
    _retryBackoffCtrl.dispose();
    _rtcHourCtrl.dispose();
    _rtcMinuteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _hostCtrl,
          decoration: const InputDecoration(labelText: 'Host'),
        ),
        TextField(
          controller: _portCtrl,
          decoration: const InputDecoration(labelText: 'Port'),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: _unitIdCtrl,
          decoration: const InputDecoration(labelText: 'Unit ID'),
          keyboardType: TextInputType.number,
        ),
        DropdownButtonFormField<ModbusAddressMode>(
          initialValue: _addressMode,
          decoration: const InputDecoration(labelText: 'Address mode'),
          items: const [
            DropdownMenuItem(
              value: ModbusAddressMode.zeroBased,
              child: Text('zero_based'),
            ),
            DropdownMenuItem(
              value: ModbusAddressMode.style4xxxx,
              child: Text('scada_4xxxx'),
            ),
          ],
          onChanged: (value) => setState(() {
            _addressMode = value ?? ModbusAddressMode.zeroBased;
          }),
        ),
        TextField(
          controller: _manifestCtrl,
          decoration: const InputDecoration(
            labelText: 'Topology manifest path',
          ),
        ),
        TextField(
          controller: _blobCtrl,
          decoration: const InputDecoration(labelText: 'Topology blob path'),
        ),
        TextField(
          controller: _semanticCtrl,
          decoration: const InputDecoration(labelText: 'Semantic catalog path'),
        ),
        TextField(
          controller: _pollCtrl,
          decoration: const InputDecoration(labelText: 'Telemetry poll ms'),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: _diagPollCtrl,
          decoration: const InputDecoration(labelText: 'Diag poll ms'),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: _responseTimeoutCtrl,
          decoration: const InputDecoration(labelText: 'Response timeout ms'),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: _retryCountCtrl,
          decoration: const InputDecoration(labelText: 'Retry count'),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: _retryBackoffCtrl,
          decoration: const InputDecoration(labelText: 'Retry backoff ms'),
          keyboardType: TextInputType.number,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Pause polling during write workflows'),
          value: _pausePollingDuringWrites,
          onChanged: (value) {
            setState(() => _pausePollingDuringWrites = value);
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: () async {
                final next = controller.config.copyWith(
                  deviceConnection: controller.config.deviceConnection.copyWith(
                    host: _hostCtrl.text.trim(),
                    port:
                        int.tryParse(_portCtrl.text.trim()) ??
                        controller.config.deviceConnection.port,
                    unitId:
                        int.tryParse(_unitIdCtrl.text.trim()) ??
                        controller.config.deviceConnection.unitId,
                  ),
                  addressMode: _addressMode,
                  localTopologyManifestPath: _manifestCtrl.text.trim(),
                  localTopologyBlobPath: _blobCtrl.text.trim(),
                  semanticCatalogPath: _semanticCtrl.text.trim(),
                  pollIntervals: controller.config.pollIntervals.copyWith(
                    telemetryMs:
                        int.tryParse(_pollCtrl.text.trim()) ??
                        controller.config.pollIntervals.telemetryMs,
                    diagMs:
                        int.tryParse(_diagPollCtrl.text.trim()) ??
                        controller.config.pollIntervals.diagMs,
                  ),
                  timeouts: controller.config.timeouts.copyWith(
                    responseMs:
                        int.tryParse(_responseTimeoutCtrl.text.trim()) ??
                        controller.config.timeouts.responseMs,
                    retryBackoffMs:
                        int.tryParse(_retryBackoffCtrl.text.trim()) ??
                        controller.config.timeouts.retryBackoffMs,
                  ),
                  transport: controller.config.transport.copyWith(
                    retryCount:
                        int.tryParse(_retryCountCtrl.text.trim()) ??
                        controller.config.transport.retryCount,
                  ),
                  featureFlags: controller.config.featureFlags.copyWith(
                    pausePollingDuringWriteWorkflows: _pausePollingDuringWrites,
                  ),
                );
                await controller.saveConfig(next);
                if (mounted) {
                  setState(() => _status = 'Settings saved');
                }
              },
              child: const Text('Save'),
            ),
            ElevatedButton(
              onPressed: () => unawaited(controller.reloadLocalTopology()),
              child: const Text('Reload topology'),
            ),
            ElevatedButton(
              onPressed: () => unawaited(controller.reconnect()),
              child: const Text('Reconnect'),
            ),
            ElevatedButton(
              onPressed: controller.canUploadTopology
                  ? () => unawaited(controller.uploadTopology())
                  : null,
              child: const Text('Upload topology'),
            ),
          ],
        ),
        if (_status.isNotEmpty) Text(_status),
        if (controller.uploadStatus != null) Text(controller.uploadStatus!),
        const Divider(height: 24),
        const Text('RTC'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _rtcHourCtrl,
                decoration: const InputDecoration(labelText: 'Hour'),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _rtcMinuteCtrl,
                decoration: const InputDecoration(labelText: 'Minute'),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: controller.canUseRtc
              ? () async {
                  try {
                    await controller.setServerRtcTime(
                      hour: int.tryParse(_rtcHourCtrl.text.trim()) ?? 0,
                      minute: int.tryParse(_rtcMinuteCtrl.text.trim()) ?? 0,
                    );
                    if (mounted) {
                      setState(() => _status = 'RTC updated');
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() => _status = 'RTC failed: $e');
                    }
                  }
                }
              : null,
          child: const Text('Set RTC'),
        ),
        if (controller.serverRtcLastError != null)
          Text('RTC error: ${controller.serverRtcLastError}'),
        const Divider(height: 24),
        const Text('Diagnostics'),
        Text('Polling paused: ${controller.pollingPaused ? 'yes' : 'no'}'),
        if (controller.diagnosticsLastUpdate != null)
          Text('Updated: ${controller.diagnosticsLastUpdate}'),
        if (controller.diagnosticsSnapshot != null) ...[
          Text(
            'TCP accept/recvTimeout/stale/malformed/send='
            '${controller.diagnosticsSnapshot!.tcpAcceptErrCount}/'
            '${controller.diagnosticsSnapshot!.tcpRecvTimeoutCount}/'
            '${controller.diagnosticsSnapshot!.tcpStaleCloseCount}/'
            '${controller.diagnosticsSnapshot!.tcpMalformedMbapCount}/'
            '${controller.diagnosticsSnapshot!.tcpSendErrCount}',
          ),
          Text('TCP last err: ${controller.diagnosticsSnapshot!.tcpLastErr}'),
          Text(
            'Boot/power/error/wdg/fault='
            '${controller.diagnosticsSnapshot!.bootCount}/'
            '${controller.diagnosticsSnapshot!.powerOnCount}/'
            '${controller.diagnosticsSnapshot!.errorHandlerCount}/'
            '${controller.diagnosticsSnapshot!.watchdogMissCount}/'
            '${controller.diagnosticsSnapshot!.faultResetCount}',
          ),
        ],
        if (controller.diagnosticsLastError != null)
          Text('Diagnostics error: ${controller.diagnosticsLastError}'),
        const Divider(height: 24),
        const Text('Trace'),
        SelectableText(
          controller.clientTrace.take(60).join('\n'),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _TabEntry {
  const _TabEntry({required this.label, required this.child});

  final String label;
  final Widget child;
}

String _formatPointValue(TopologyPoint point, PointTelemetryValue? telemetry) {
  if (telemetry == null || !telemetry.isUsable) {
    return 'N/A';
  }
  if (point.semanticName == 'light_status_bits') {
    return '${telemetry.value.round()}';
  }
  if (point.semanticName == 'light_output') {
    return '${telemetry.value.round()}';
  }
  if (point.semanticName == 'current_dli') {
    return telemetry.value.toStringAsFixed(2);
  }
  switch (point.pointType) {
    case 6:
      return '${telemetry.value.round()}';
    case 1:
    case 2:
    case 3:
    case 4:
      return telemetry.value.toStringAsFixed(0);
    default:
      return telemetry.value.toStringAsFixed(2);
  }
}

String _formatSemanticField(SemanticFieldView field) {
  final telemetry = field.telemetry;
  if (field.point == null) {
    return 'unsupported';
  }
  if (telemetry == null || !telemetry.isUsable) {
    return 'N/A';
  }
  final suffix = field.unit.isEmpty ? '' : ' ${field.unit}';
  return '${telemetry.value.toStringAsFixed(field.decimals)}$suffix';
}

String _formatLightingFeedbackField(SemanticFieldView field) {
  final telemetry = field.telemetry;
  if (field.point == null) {
    return 'unsupported';
  }
  if (telemetry == null || !telemetry.hasValidFlag) {
    return 'N/A';
  }
  switch (field.semanticName) {
    case 'light_status_bits':
      return '${telemetry.value.round()}';
    case 'light_output':
      return '${telemetry.value.round()} %';
    default:
      final suffix = field.unit.isEmpty ? '' : ' ${field.unit}';
      return '${telemetry.value.toStringAsFixed(field.decimals)}$suffix';
  }
}

String _lightingFeedbackSubtitle(SemanticFieldView field) {
  final point = field.point;
  if (point == null) {
    return 'Point contract missing';
  }
  final telemetry = field.telemetry;
  if (telemetry == null) {
    return 'publish_index=${point.publishIndex} quality=- age=- flags=-';
  }
  return 'publish_index=${point.publishIndex} quality=${telemetry.quality} '
      'age=${telemetry.ageSec}s flags=0x${telemetry.flags.toRadixString(16).toUpperCase()}';
}

String _formatHhmm(int hhmm) {
  final hour = (hhmm ~/ 100).clamp(0, 23);
  final minute = (hhmm % 100).clamp(0, 59);
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
