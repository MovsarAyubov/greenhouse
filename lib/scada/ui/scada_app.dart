import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../l10n/app_localizations.dart';
import '../models/lighting_schedule_models.dart';
import '../models/scada_models.dart';
import '../models/topology_models.dart';
import '../services/modbus_tcp_client.dart';
import '../services/scada_controller.dart';

class ScadaApp extends StatefulWidget {
  const ScadaApp({super.key});

  @override
  State<ScadaApp> createState() => _ScadaAppState();
}

class _ScadaAppState extends State<ScadaApp> {
  late final ScadaController controller;
  Locale _locale = const Locale('ru');

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
      locale: _locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final l10n = context.l10n;
          final tabs = <_TabEntry>[
            _TabEntry(
              label: l10n.dashboard,
              child: _DashboardTab(controller: controller),
            ),
            ...controller.zoneModules.map(
              (module) => _TabEntry(
                label: l10n.zone(module.zoneId),
                child: _ZoneModuleTab(controller: controller, module: module),
              ),
            ),
            if (controller.weatherModules.isNotEmpty)
              _TabEntry(
                label: l10n.weather,
                child: _WeatherTab(controller: controller),
              ),
            _TabEntry(
              label: l10n.settings,
              child: _SettingsTab(controller: controller),
            ),
          ];
          return DefaultTabController(
            length: tabs.length,
            child: Scaffold(
              appBar: AppBar(
                title: Text(l10n.appTitle),
                bottom: TabBar(
                  isScrollable: true,
                  tabs: tabs.map((tab) => Tab(text: tab.label)).toList(),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Locale>(
                        value: _locale,
                        items: [
                          DropdownMenuItem(
                            value: const Locale('ru'),
                            child: Text(l10n.russian),
                          ),
                          DropdownMenuItem(
                            value: const Locale('en'),
                            child: Text(l10n.english),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _locale = value);
                          }
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: Text(
                        controller.connected
                            ? l10n.connected
                            : l10n.disconnected,
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
    final l10n = context.l10n;
    final metadata = controller.deviceTopologyMetadata;
    final store = controller.topologySnapshot;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoCard(
          title: l10n.session,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.state(controller.compatibility.state.name)),
              Text(controller.compatibility.message),
              if (controller.lastError != null)
                Text(l10n.lastError(controller.lastError!)),
              Text(l10n.rtc(controller.serverRtcText)),
            ],
          ),
        ),
        _InfoCard(
          title: l10n.deviceTopology,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.active(metadata?.isActive == true)),
              Text(
                l10n.version(
                  metadata == null
                      ? '-'
                      : '${metadata.versionMajor}.${metadata.versionMinor}',
                ),
              ),
              Text(l10n.generation('${metadata?.activeGeneration ?? '-'}')),
              Text(l10n.sizeBytes('${metadata?.activeSizeBytes ?? '-'}')),
            ],
          ),
        ),
        _InfoCard(
          title: l10n.localTopology,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.manifest(store.hasManifest)),
              if (store.manifest != null)
                Text(
                  'schema=${store.manifest!.schemaVersion} generation=${store.manifest!.generation}',
                ),
              if (store.manifestError != null)
                Text(l10n.manifestError(store.manifestError!)),
              Text(l10n.semanticCatalog(store.hasSemanticCatalog)),
              if (store.semanticCatalogPath != null)
                Text(l10n.semanticPath(store.semanticCatalogPath!)),
              if (store.semanticCatalogError != null)
                Text(l10n.semanticError(store.semanticCatalogError!)),
              Text(l10n.blob(store.hasBlob)),
              if (store.blobCrc32 != null)
                Text(
                  'Blob CRC32: 0x${store.blobCrc32!.toRadixString(16).toUpperCase()}',
                ),
              if (store.blobError != null)
                Text(l10n.blobError(store.blobError!)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _InfoCard(
          title: l10n.topologyInventory,
          child: Column(
            children: controller.moduleSummaries
                .map(
                  (summary) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(summary.module.title),
                    subtitle: Text(
                      l10n.moduleSummary(
                        moduleId: summary.module.moduleId,
                        slaveId: summary.module.slaveId,
                        points: summary.pointCount,
                        schedule: summary.scheduleAvailable,
                      ),
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
    final l10n = context.l10n;
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
              Text(l10n.moduleIdSlave(module.moduleId, module.slaveId)),
              Text(
                l10n.zoneCapability(
                  module.zoneId,
                  module.capabilityMask.toRadixString(16),
                ),
              ),
              Text(
                l10n.onlineStale(
                  online: status?.online == true,
                  stale: status?.stale == true,
                ),
              ),
              if (status != null)
                Text(
                  l10n.slaveAgeErrors(
                    age: status.lastOkAgeSec,
                    timeout: status.errTimeout,
                    crc: status.errCrc,
                    exception: status.errException,
                  ),
                ),
            ],
          ),
        ),
        _LightingFeedbackCard(fields: lightingFeedback),
        _InfoCard(
          title: l10n.telemetry,
          child: Column(
            children: points
                .map(
                  (item) => ListTile(
                    dense: true,
                    title: Text(item.point.displayName),
                    subtitle: Text(
                      l10n.pointRow(
                        publishIndex: item.point.publishIndex,
                        quality: item.telemetry?.quality ?? '-',
                        age: item.telemetry?.ageSec ?? '-',
                      ),
                    ),
                    trailing: Text(
                      _formatPointValue(context, item.point, item.telemetry),
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
          lightingFeedback: lightingFeedback,
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
                          _formatSemanticField(context, field),
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
    final l10n = context.l10n;
    return _InfoCard(
      title: l10n.lightingFeedback,
      child: Column(
        children: fields
            .map(
              (field) => ListTile(
                dense: true,
                title: Text(field.label),
                subtitle: Text(_lightingFeedbackSubtitle(context, field)),
                trailing: Text(
                  _formatLightingFeedbackField(context, field),
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
    required this.lightingFeedback,
  });

  final ScadaController controller;
  final TopologyModule module;
  final LightingScheduleStatus status;
  final String? disabledReason;
  final List<SemanticFieldView> lightingFeedback;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final draft = status.draft;
    final runtime = _LightingRuntimeView.fromFields(lightingFeedback);
    return _InfoCard(
      title: l10n.lightingSetpoints,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LightingRuntimeSummary(runtime: runtime),
          const SizedBox(height: 12),
          _buildRelaySection(
            context,
            title: l10n.relay1,
            relay: draft.relay1,
            onChanged: (relay) => controller.updateLightingDraft(
              module.moduleId,
              (current) => current.copyWith(relay1: relay),
            ),
          ),
          const SizedBox(height: 8),
          _buildRelaySection(
            context,
            title: l10n.relay2,
            relay: draft.relay2,
            onChanged: (relay) => controller.updateLightingDraft(
              module.moduleId,
              (current) => current.copyWith(relay2: relay),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: '${draft.hysteresisSec}',
            decoration: InputDecoration(
              labelText: l10n.hysteresis,
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
          Text(l10n.recommendedWrite),
          if (disabledReason != null)
            Text(disabledReason!, style: const TextStyle(color: Colors.orange)),
          ElevatedButton(
            onPressed: disabledReason == null
                ? () => unawaited(
                    controller.sendScheduleForModule(module.moduleId),
                  )
                : null,
            child: Text(l10n.sendSetpoints),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.scheduleStatus(
              phase: status.phase.name,
              trigger: status.trigger,
              applied: status.lastAppliedTrigger,
              result: status.lastResult,
              io: status.lastIoErr,
            ),
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
          title: Text(context.l10n.enabled),
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
              child: Text(context.l10n.onAt(_formatHhmm(relay.onHhmm))),
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
              child: Text(context.l10n.offAt(_formatHhmm(relay.offHhmm))),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: '${relay.thresholdWm2}',
                decoration: InputDecoration(
                  labelText: context.l10n.threshold,
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
          decoration: InputDecoration(labelText: context.l10n.dliLimit),
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

class _LightingRuntimeSummary extends StatelessWidget {
  const _LightingRuntimeSummary({required this.runtime});

  final _LightingRuntimeView runtime;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = runtime.hasValidOutput
        ? (runtime.lightOutputPct > 0 ? Colors.green : Colors.grey)
        : Colors.orange;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(
          avatar: Icon(
            runtime.lightOutputPct > 0
                ? Icons.lightbulb
                : Icons.lightbulb_outline,
            color: color,
            size: 18,
          ),
          label: Text(runtime.outputLabel(l10n)),
        ),
        Chip(label: Text(l10n.relayState(1, runtime.relay1On))),
        Chip(label: Text(l10n.relayState(2, runtime.relay2On))),
        Chip(label: Text(l10n.dli(runtime.dliLabel(l10n)))),
      ],
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
    final l10n = context.l10n;
    final controller = widget.controller;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _hostCtrl,
          decoration: InputDecoration(labelText: l10n.host),
        ),
        TextField(
          controller: _portCtrl,
          decoration: InputDecoration(labelText: l10n.port),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: _unitIdCtrl,
          decoration: InputDecoration(labelText: l10n.unitId),
          keyboardType: TextInputType.number,
        ),
        DropdownButtonFormField<ModbusAddressMode>(
          initialValue: _addressMode,
          decoration: InputDecoration(labelText: l10n.addressMode),
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
          decoration: InputDecoration(labelText: l10n.topologyManifestPath),
        ),
        TextField(
          controller: _blobCtrl,
          decoration: InputDecoration(labelText: l10n.topologyBlobPath),
        ),
        TextField(
          controller: _semanticCtrl,
          decoration: InputDecoration(labelText: l10n.semanticCatalogPath),
        ),
        TextField(
          controller: _pollCtrl,
          decoration: InputDecoration(labelText: l10n.telemetryPollMs),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: _diagPollCtrl,
          decoration: InputDecoration(labelText: l10n.diagPollMs),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: _responseTimeoutCtrl,
          decoration: InputDecoration(labelText: l10n.responseTimeoutMs),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: _retryCountCtrl,
          decoration: InputDecoration(labelText: l10n.retryCount),
          keyboardType: TextInputType.number,
        ),
        TextField(
          controller: _retryBackoffCtrl,
          decoration: InputDecoration(labelText: l10n.retryBackoffMs),
          keyboardType: TextInputType.number,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.pausePollingDuringWrites),
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
                  setState(() => _status = l10n.settingsSaved);
                }
              },
              child: Text(l10n.save),
            ),
            ElevatedButton(
              onPressed: () => unawaited(controller.reloadLocalTopology()),
              child: Text(l10n.reloadTopology),
            ),
            ElevatedButton(
              onPressed: () => unawaited(controller.reconnect()),
              child: Text(l10n.reconnect),
            ),
            ElevatedButton(
              onPressed: controller.canUploadTopology
                  ? () => unawaited(controller.uploadTopology())
                  : null,
              child: Text(l10n.uploadTopology),
            ),
          ],
        ),
        if (_status.isNotEmpty) Text(_status),
        if (controller.uploadStatus != null) Text(controller.uploadStatus!),
        const Divider(height: 24),
        Text(l10n.rtcSection),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _rtcHourCtrl,
                decoration: InputDecoration(labelText: l10n.hour),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _rtcMinuteCtrl,
                decoration: InputDecoration(labelText: l10n.minute),
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
                      setState(() => _status = l10n.rtcUpdated);
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() => _status = l10n.rtcFailed('$e'));
                    }
                  }
                }
              : null,
          child: Text(l10n.setRtc),
        ),
        if (controller.serverRtcLastError != null)
          Text(l10n.rtcError(controller.serverRtcLastError!)),
        const Divider(height: 24),
        Text(l10n.diagnostics),
        Text(l10n.pollingPaused(controller.pollingPaused)),
        if (controller.diagnosticsLastUpdate != null)
          Text(l10n.updated('${controller.diagnosticsLastUpdate}')),
        if (controller.diagnosticsSnapshot != null) ...[
          Text(
            l10n.tcpCounters(
              accept: controller.diagnosticsSnapshot!.tcpAcceptErrCount,
              recvTimeout: controller.diagnosticsSnapshot!.tcpRecvTimeoutCount,
              stale: controller.diagnosticsSnapshot!.tcpStaleCloseCount,
              malformed: controller.diagnosticsSnapshot!.tcpMalformedMbapCount,
              send: controller.diagnosticsSnapshot!.tcpSendErrCount,
            ),
          ),
          Text(l10n.tcpLastErr(controller.diagnosticsSnapshot!.tcpLastErr)),
          Text(
            l10n.bootCounters(
              boot: controller.diagnosticsSnapshot!.bootCount,
              power: controller.diagnosticsSnapshot!.powerOnCount,
              error: controller.diagnosticsSnapshot!.errorHandlerCount,
              watchdog: controller.diagnosticsSnapshot!.watchdogMissCount,
              fault: controller.diagnosticsSnapshot!.faultResetCount,
            ),
          ),
        ],
        if (controller.diagnosticsLastError != null)
          Text(l10n.diagnosticsError(controller.diagnosticsLastError!)),
        const Divider(height: 24),
        Text(l10n.trace),
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

class _LightingRuntimeView {
  const _LightingRuntimeView({
    required this.lightOutputPct,
    required this.statusBits,
    required this.currentDli,
    required this.hasValidOutput,
  });

  final int lightOutputPct;
  final int statusBits;
  final double? currentDli;
  final bool hasValidOutput;

  bool get relay1On => (statusBits & 0x0001) != 0;
  bool get relay2On => (statusBits & 0x0002) != 0;
  String outputLabel(AppLocalizations l10n) =>
      hasValidOutput ? l10n.outputPct(lightOutputPct) : l10n.outputNa;
  String dliLabel(AppLocalizations l10n) =>
      currentDli == null ? l10n.notAvailable : currentDli!.toStringAsFixed(2);

  static _LightingRuntimeView fromFields(List<SemanticFieldView> fields) {
    PointTelemetryValue? output;
    PointTelemetryValue? bits;
    PointTelemetryValue? dli;
    for (final field in fields) {
      switch (field.semanticName) {
        case 'light_output':
          output = field.telemetry;
        case 'light_status_bits':
          bits = field.telemetry;
        case 'current_dli':
          dli = field.telemetry;
      }
    }
    return _LightingRuntimeView(
      lightOutputPct: output?.value.round() ?? 0,
      statusBits: bits?.value.round() ?? 0,
      currentDli: dli?.isUsable == true ? dli!.value : null,
      hasValidOutput: output?.isUsable == true,
    );
  }
}

String _formatPointValue(
  BuildContext context,
  TopologyPoint point,
  PointTelemetryValue? telemetry,
) {
  if (telemetry == null || !telemetry.isUsable) {
    return context.l10n.notAvailable;
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

String _formatSemanticField(BuildContext context, SemanticFieldView field) {
  final l10n = context.l10n;
  final telemetry = field.telemetry;
  if (field.point == null) {
    return l10n.unsupported;
  }
  if (telemetry == null || !telemetry.isUsable) {
    return l10n.notAvailable;
  }
  final suffix = field.unit.isEmpty ? '' : ' ${field.unit}';
  return '${telemetry.value.toStringAsFixed(field.decimals)}$suffix';
}

String _formatLightingFeedbackField(
  BuildContext context,
  SemanticFieldView field,
) {
  final l10n = context.l10n;
  final telemetry = field.telemetry;
  if (field.point == null) {
    return l10n.unsupported;
  }
  if (telemetry == null || !telemetry.hasValidFlag) {
    return l10n.notAvailable;
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

String _lightingFeedbackSubtitle(
  BuildContext context,
  SemanticFieldView field,
) {
  final l10n = context.l10n;
  final point = field.point;
  if (point == null) {
    return l10n.pointContractMissing;
  }
  final telemetry = field.telemetry;
  if (telemetry == null) {
    return l10n.fieldRow(
      publishIndex: point.publishIndex,
      quality: '-',
      age: '-',
      flags: '-',
    );
  }
  return l10n.fieldRow(
    publishIndex: point.publishIndex,
    quality: telemetry.quality,
    age: telemetry.ageSec,
    flags: '0x${telemetry.flags.toRadixString(16).toUpperCase()}',
  );
}

String _formatHhmm(int hhmm) {
  final hour = (hhmm ~/ 100).clamp(0, 23);
  final minute = (hhmm % 100).clamp(0, 59);
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
