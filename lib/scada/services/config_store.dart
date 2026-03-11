import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/scada_models.dart';
import 'modbus_tcp_client.dart';

class ConfigStore {
  static const String _key = 'scada_topology_config_v2';

  Future<ScadaConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final defaults = ScadaConfig.defaults();
    if (raw == null || raw.isEmpty) {
      return defaults;
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final deviceMap = _mapValue(map['device_connection']);
      final pollMap = _mapValue(map['poll_intervals']);
      final timeoutMap = _mapValue(map['timeouts']);
      final featureMap = _mapValue(map['feature_flags']);
      return defaults.copyWith(
        deviceConnection: defaults.deviceConnection.copyWith(
          host:
              (deviceMap['host'] as String?) ?? defaults.deviceConnection.host,
          port: _readInt(deviceMap['port']) ?? defaults.deviceConnection.port,
          unitId:
              _readInt(deviceMap['unit_id']) ?? defaults.deviceConnection.unitId,
        ),
        addressMode: _readAddressMode(map['address_mode']) ?? defaults.addressMode,
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
          telemetryMs:
              _readInt(pollMap['telemetry_ms']) ?? defaults.pollIntervals.telemetryMs,
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
          responseMs:
              _readInt(timeoutMap['response_ms']) ?? defaults.timeouts.responseMs,
          commandMs:
              _readInt(timeoutMap['command_ms']) ?? defaults.timeouts.commandMs,
          uploadChunkMs:
              _readInt(timeoutMap['upload_chunk_ms']) ??
              defaults.timeouts.uploadChunkMs,
          uploadCommitMs:
              _readInt(timeoutMap['upload_commit_ms']) ??
              defaults.timeouts.uploadCommitMs,
        ),
        featureFlags: defaults.featureFlags.copyWith(
          allowTelemetryOnGenerationMismatch:
              featureMap['allow_telemetry_on_generation_mismatch'] as bool? ??
              defaults.featureFlags.allowTelemetryOnGenerationMismatch,
          showUnsupportedPoints:
              featureMap['show_unsupported_points'] as bool? ??
              defaults.featureFlags.showUnsupportedPoints,
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
        'command_poll_ms': config.pollIntervals.commandPollMs,
        'upload_poll_ms': config.pollIntervals.uploadPollMs,
      },
      'timeouts': <String, dynamic>{
        'connect_ms': config.timeouts.connectMs,
        'response_ms': config.timeouts.responseMs,
        'command_ms': config.timeouts.commandMs,
        'upload_chunk_ms': config.timeouts.uploadChunkMs,
        'upload_commit_ms': config.timeouts.uploadCommitMs,
      },
      'feature_flags': <String, dynamic>{
        'allow_telemetry_on_generation_mismatch':
            config.featureFlags.allowTelemetryOnGenerationMismatch,
        'show_unsupported_points': config.featureFlags.showUnsupportedPoints,
      },
    };
    await prefs.setString(_key, jsonEncode(payload));
  }

  Map<String, dynamic> _mapValue(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, val) => MapEntry(key.toString(), val),
      );
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
