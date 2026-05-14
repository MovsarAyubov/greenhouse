import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/lighting_schedule_models.dart';
import '../models/scada_models.dart';
import '../models/window_setpoint_models.dart';
import 'modbus_tcp_client.dart';

class ConfigStore {
  static const String _key = 'scada_topology_config_v3';
  static const String _legacyKey = 'scada_topology_config_v2';
  static const String _lightingDraftsKey = 'scada_lighting_drafts_v1';
  static const String _windowDraftsKey = 'scada_window_setpoint_drafts_v1';
  static const int _minResponseTimeoutMs = 1000;
  static const int _minDiagPollMs = 30000;
  static const int _legacyTelemetryMs = 5000;
  static const int _legacyResponseTimeoutMs = 3000;
  static const int _legacyRetryCount = 1;
  static const int _previousFastTelemetryMs = 1000;
  static const int _previousFastResponseTimeoutMs = 1000;
  static const int _previousFastRetryCount = 0;

  Future<ScadaConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = ScadaConfig.defaults();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      final config = _applyEnvironmentOverrides(
        _decodeConfig(
          raw: raw,
          defaults: defaults,
          migrateLegacyDefaults: false,
        ),
        defaults,
      );
      if (_usesPreviousFastTelemetryProfile(config)) {
        final migrated = config.copyWith(
          pollIntervals: config.pollIntervals.copyWith(
            telemetryMs: defaults.pollIntervals.telemetryMs,
          ),
        );
        await save(migrated);
        return migrated;
      }
      return config;
    }

    final legacyRaw = prefs.getString(_legacyKey);
    if (legacyRaw == null || legacyRaw.isEmpty) {
      return defaults;
    }
    final migrated = _applyEnvironmentOverrides(
      _decodeConfig(
        raw: legacyRaw,
        defaults: defaults,
        migrateLegacyDefaults: true,
      ),
      defaults,
    );
    await save(migrated);
    await prefs.remove(_legacyKey);
    return migrated;
  }

  ScadaConfig _applyEnvironmentOverrides(
    ScadaConfig config,
    ScadaConfig defaults,
  ) {
    return config.copyWith(
      deviceConnection: defaults.deviceConnection,
      addressMode: defaults.addressMode,
      localTopologyManifestPath: defaults.localTopologyManifestPath.isNotEmpty
          ? defaults.localTopologyManifestPath
          : config.localTopologyManifestPath,
      localTopologyBlobPath: defaults.localTopologyBlobPath.isNotEmpty
          ? defaults.localTopologyBlobPath
          : config.localTopologyBlobPath,
      semanticCatalogPath: defaults.semanticCatalogPath.isNotEmpty
          ? defaults.semanticCatalogPath
          : config.semanticCatalogPath,
    );
  }

  ScadaConfig _decodeConfig({
    required String raw,
    required ScadaConfig defaults,
    required bool migrateLegacyDefaults,
  }) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final deviceMap = _mapValue(map['device_connection']);
      final pollMap = _mapValue(map['poll_intervals']);
      final timeoutMap = _mapValue(map['timeouts']);
      final transportMap = _mapValue(map['transport']);
      final featureMap = _mapValue(map['feature_flags']);
      final telemetryMs = _normalizeTelemetryMs(
        _readInt(pollMap['telemetry_ms']),
        defaults.pollIntervals.telemetryMs,
        migrateLegacyDefaults: migrateLegacyDefaults,
      );
      final diagMs =
          _readInt(pollMap['diag_ms']) ?? defaults.pollIntervals.diagMs;
      final responseMs = _normalizeResponseTimeoutMs(
        _readInt(timeoutMap['response_ms']),
        defaults.timeouts.responseMs,
        migrateLegacyDefaults: migrateLegacyDefaults,
      );
      final retryCount = _normalizeRetryCount(
        _readInt(transportMap['retry_count']),
        defaults.transport.retryCount,
        migrateLegacyDefaults: migrateLegacyDefaults,
      );
      return defaults.copyWith(
        deviceConnection: defaults.deviceConnection.copyWith(
          host:
              (deviceMap['host'] as String?) ?? defaults.deviceConnection.host,
          port: _readInt(deviceMap['port']) ?? defaults.deviceConnection.port,
          unitId:
              _readInt(deviceMap['unit_id']) ??
              defaults.deviceConnection.unitId,
        ),
        addressMode:
            _readAddressMode(map['address_mode']) ?? defaults.addressMode,
        localTopologyManifestPath:
            (map['local_topology_manifest_path'] as String?) ??
            defaults.localTopologyManifestPath,
        localTopologyBlobPath:
            (map['local_topology_blob_path'] as String?) ??
            defaults.localTopologyBlobPath,
        semanticCatalogPath:
            (map['semantic_catalog_path'] as String?) ??
            defaults.semanticCatalogPath,
        pollIntervals: defaults.pollIntervals.copyWith(
          telemetryMs: telemetryMs,
          diagMs: diagMs < _minDiagPollMs ? _minDiagPollMs : diagMs,
          commandPollMs:
              _readInt(pollMap['command_poll_ms']) ??
              defaults.pollIntervals.commandPollMs,
          uploadPollMs:
              _readInt(pollMap['upload_poll_ms']) ??
              defaults.pollIntervals.uploadPollMs,
        ),
        timeouts: defaults.timeouts.copyWith(
          connectMs:
              _readInt(timeoutMap['connect_ms']) ?? defaults.timeouts.connectMs,
          responseMs: responseMs < _minResponseTimeoutMs
              ? _minResponseTimeoutMs
              : responseMs,
          retryBackoffMs:
              _readInt(timeoutMap['retry_backoff_ms']) ??
              defaults.timeouts.retryBackoffMs,
          commandMs:
              _readInt(timeoutMap['command_ms']) ?? defaults.timeouts.commandMs,
          uploadChunkMs:
              _readInt(timeoutMap['upload_chunk_ms']) ??
              defaults.timeouts.uploadChunkMs,
          uploadCommitMs:
              _readInt(timeoutMap['upload_commit_ms']) ??
              defaults.timeouts.uploadCommitMs,
        ),
        transport: defaults.transport.copyWith(retryCount: retryCount),
        featureFlags: defaults.featureFlags.copyWith(
          allowTelemetryOnGenerationMismatch:
              featureMap['allow_telemetry_on_generation_mismatch'] as bool? ??
              defaults.featureFlags.allowTelemetryOnGenerationMismatch,
          showUnsupportedPoints:
              featureMap['show_unsupported_points'] as bool? ??
              defaults.featureFlags.showUnsupportedPoints,
          pausePollingDuringWriteWorkflows:
              featureMap['pause_polling_during_write_workflows'] as bool? ??
              defaults.featureFlags.pausePollingDuringWriteWorkflows,
        ),
      );
    } catch (_) {
      return defaults;
    }
  }

  Future<void> save(ScadaConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'device_connection': <String, dynamic>{
        'host': config.deviceConnection.host,
        'port': config.deviceConnection.port,
        'unit_id': config.deviceConnection.unitId,
      },
      'address_mode': config.addressMode.name,
      'local_topology_manifest_path': config.localTopologyManifestPath,
      'local_topology_blob_path': config.localTopologyBlobPath,
      'semantic_catalog_path': config.semanticCatalogPath,
      'poll_intervals': <String, dynamic>{
        'telemetry_ms': config.pollIntervals.telemetryMs,
        'diag_ms': config.pollIntervals.diagMs,
        'command_poll_ms': config.pollIntervals.commandPollMs,
        'upload_poll_ms': config.pollIntervals.uploadPollMs,
      },
      'timeouts': <String, dynamic>{
        'connect_ms': config.timeouts.connectMs,
        'response_ms': config.timeouts.responseMs,
        'retry_backoff_ms': config.timeouts.retryBackoffMs,
        'command_ms': config.timeouts.commandMs,
        'upload_chunk_ms': config.timeouts.uploadChunkMs,
        'upload_commit_ms': config.timeouts.uploadCommitMs,
      },
      'transport': <String, dynamic>{
        'retry_count': config.transport.retryCount,
      },
      'feature_flags': <String, dynamic>{
        'allow_telemetry_on_generation_mismatch':
            config.featureFlags.allowTelemetryOnGenerationMismatch,
        'show_unsupported_points': config.featureFlags.showUnsupportedPoints,
        'pause_polling_during_write_workflows':
            config.featureFlags.pausePollingDuringWriteWorkflows,
      },
    };
    await prefs.setString(_key, jsonEncode(payload));
    await prefs.remove(_legacyKey);
  }

  Future<Map<int, LightingScheduleDraft>> loadLightingDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lightingDraftsKey);
    if (raw == null || raw.isEmpty) {
      return <int, LightingScheduleDraft>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <int, LightingScheduleDraft>{};
      }
      final drafts = <int, LightingScheduleDraft>{};
      for (final entry in decoded.entries) {
        final moduleId = int.tryParse(entry.key.toString());
        final draft = LightingScheduleDraft.fromJson(entry.value);
        if (moduleId == null || draft == null) {
          continue;
        }
        drafts[moduleId] = draft;
      }
      return drafts;
    } catch (_) {
      return <int, LightingScheduleDraft>{};
    }
  }

  Future<void> saveLightingDrafts(
    Map<int, LightingScheduleDraft> drafts,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (drafts.isEmpty) {
      await prefs.remove(_lightingDraftsKey);
      return;
    }
    final payload = <String, dynamic>{
      for (final entry in drafts.entries)
        entry.key.toString(): entry.value.toJson(),
    };
    await prefs.setString(_lightingDraftsKey, jsonEncode(payload));
  }

  Future<Map<int, WindowSetpointDraft>> loadWindowSetpointDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_windowDraftsKey);
    if (raw == null || raw.isEmpty) {
      return <int, WindowSetpointDraft>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <int, WindowSetpointDraft>{};
      }
      final drafts = <int, WindowSetpointDraft>{};
      for (final entry in decoded.entries) {
        final moduleId = int.tryParse(entry.key.toString());
        final draft = WindowSetpointDraft.fromJson(entry.value);
        if (moduleId == null || draft == null) {
          continue;
        }
        drafts[moduleId] = draft;
      }
      return drafts;
    } catch (_) {
      return <int, WindowSetpointDraft>{};
    }
  }

  Future<void> saveWindowSetpointDrafts(
    Map<int, WindowSetpointDraft> drafts,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (drafts.isEmpty) {
      await prefs.remove(_windowDraftsKey);
      return;
    }
    final payload = <String, dynamic>{
      for (final entry in drafts.entries)
        entry.key.toString(): entry.value.toJson(),
    };
    await prefs.setString(_windowDraftsKey, jsonEncode(payload));
  }

  Map<String, dynamic> _mapValue(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return <String, dynamic>{};
  }

  int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  int _normalizeTelemetryMs(
    int? value,
    int defaultValue, {
    required bool migrateLegacyDefaults,
  }) {
    if (value == null) {
      return defaultValue;
    }
    if (migrateLegacyDefaults && value == _legacyTelemetryMs) {
      return defaultValue;
    }
    return value;
  }

  int _normalizeResponseTimeoutMs(
    int? value,
    int defaultValue, {
    required bool migrateLegacyDefaults,
  }) {
    final effective = migrateLegacyDefaults && value == _legacyResponseTimeoutMs
        ? defaultValue
        : (value ?? defaultValue);
    return effective < _minResponseTimeoutMs
        ? _minResponseTimeoutMs
        : effective;
  }

  int _normalizeRetryCount(
    int? value,
    int defaultValue, {
    required bool migrateLegacyDefaults,
  }) {
    if (value == null) {
      return defaultValue;
    }
    if (migrateLegacyDefaults && value == _legacyRetryCount) {
      return defaultValue;
    }
    return value;
  }

  bool _usesPreviousFastTelemetryProfile(ScadaConfig config) {
    return config.pollIntervals.telemetryMs == _previousFastTelemetryMs &&
        config.timeouts.responseMs == _previousFastResponseTimeoutMs &&
        config.transport.retryCount == _previousFastRetryCount;
  }

  ModbusAddressMode? _readAddressMode(Object? value) {
    final text = value?.toString().trim().toLowerCase();
    switch (text) {
      case 'zero_based':
      case 'zerobased':
      case 'zero-based':
        return ModbusAddressMode.zeroBased;
      case 'scada_4xxxx':
      case 'style4xxxx':
      case '4xxxx':
        return ModbusAddressMode.style4xxxx;
      default:
        return null;
    }
  }
}
