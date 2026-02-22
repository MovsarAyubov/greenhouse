import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/scada_models.dart';

class ConfigStore {
  static const String _key = 'scada_config_v1';

  Future<ScadaConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return ScadaConfig.defaults();
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final defaults = ScadaConfig.defaults();
      final sensorNames = (map['sensorNames'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList();
      final outputNames = (map['outputNames'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList();
      return defaults.copyWith(
        masterIp: (map['masterIp'] as String?) ?? defaults.masterIp,
        masterPort: (map['masterPort'] as int?) ?? defaults.masterPort,
        pollPeriodMs: (map['pollPeriodMs'] as int?) ?? defaults.pollPeriodMs,
        staleThresholdSec:
            (map['staleThresholdSec'] as int?) ?? defaults.staleThresholdSec,
        logPeriodSec: (map['logPeriodSec'] as int?) ?? defaults.logPeriodSec,
        sensorNames: sensorNames.length == 9
            ? sensorNames
            : defaults.sensorNames,
        outputNames: outputNames.length == 16
            ? outputNames
            : defaults.outputNames,
      );
    } catch (_) {
      return ScadaConfig.defaults();
    }
  }

  Future<void> save(ScadaConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'masterIp': config.masterIp,
      'masterPort': config.masterPort,
      'pollPeriodMs': config.pollPeriodMs,
      'staleThresholdSec': config.staleThresholdSec,
      'logPeriodSec': config.logPeriodSec,
      'sensorNames': config.sensorNames,
      'outputNames': config.outputNames,
    };
    await prefs.setString(_key, jsonEncode(payload));
  }
}
