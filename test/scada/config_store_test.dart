import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/scada/models/lighting_schedule_models.dart';
import 'package:greenhouse/scada/services/config_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy v2 config migrates polling profile to current defaults', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'scada_topology_config_v2': jsonEncode(<String, dynamic>{
        'device_connection': <String, dynamic>{
          'host': '10.0.0.7',
          'port': 502,
          'unit_id': 3,
        },
        'address_mode': 'zero_based',
        'local_topology_manifest_path': 'C:\\topology.json',
        'local_topology_blob_path': 'C:\\topology.bin',
        'semantic_catalog_path': 'C:\\semantics.json',
        'poll_intervals': <String, dynamic>{
          'telemetry_ms': 5000,
          'diag_ms': 30000,
          'command_poll_ms': 500,
          'upload_poll_ms': 100,
        },
        'timeouts': <String, dynamic>{
          'connect_ms': 4000,
          'response_ms': 3000,
          'retry_backoff_ms': 100,
          'command_ms': 25000,
          'upload_chunk_ms': 3000,
          'upload_commit_ms': 15000,
        },
        'transport': <String, dynamic>{'retry_count': 1},
        'feature_flags': <String, dynamic>{
          'allow_telemetry_on_generation_mismatch': true,
          'show_unsupported_points': true,
          'pause_polling_during_write_workflows': true,
        },
      }),
    });

    final store = ConfigStore();
    final config = await store.load();
    final prefs = await SharedPreferences.getInstance();

    expect(config.deviceConnection.host, '10.0.0.7');
    expect(config.deviceConnection.unitId, 3);
    expect(config.localTopologyManifestPath, 'C:\\topology.json');
    expect(config.pollIntervals.telemetryMs, 5000);
    expect(config.timeouts.responseMs, 1000);
    expect(config.transport.retryCount, 0);
    expect(prefs.getString('scada_topology_config_v3'), isNotNull);
    expect(prefs.getString('scada_topology_config_v2'), isNull);
  });

  test('saved v3 fast telemetry profile is normalized to 5000 ms', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'scada_topology_config_v3': jsonEncode(<String, dynamic>{
        'device_connection': <String, dynamic>{
          'host': '10.0.0.7',
          'port': 502,
          'unit_id': 3,
        },
        'address_mode': 'zero_based',
        'local_topology_manifest_path': '',
        'local_topology_blob_path': '',
        'semantic_catalog_path': '',
        'poll_intervals': <String, dynamic>{
          'telemetry_ms': 1000,
          'diag_ms': 30000,
          'command_poll_ms': 500,
          'upload_poll_ms': 100,
        },
        'timeouts': <String, dynamic>{
          'connect_ms': 4000,
          'response_ms': 1000,
          'retry_backoff_ms': 100,
          'command_ms': 25000,
          'upload_chunk_ms': 3000,
          'upload_commit_ms': 15000,
        },
        'transport': <String, dynamic>{'retry_count': 0},
        'feature_flags': <String, dynamic>{
          'allow_telemetry_on_generation_mismatch': true,
          'show_unsupported_points': true,
          'pause_polling_during_write_workflows': true,
        },
      }),
    });

    final store = ConfigStore();
    final config = await store.load();
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(
      prefs.getString('scada_topology_config_v3')!,
    ) as Map<String, dynamic>;
    final poll = saved['poll_intervals'] as Map<String, dynamic>;

    expect(config.pollIntervals.telemetryMs, 5000);
    expect(config.timeouts.responseMs, 1000);
    expect(config.transport.retryCount, 0);
    expect(poll['telemetry_ms'], 5000);
  });

  test('explicit v3 polling settings are preserved', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'scada_topology_config_v3': jsonEncode(<String, dynamic>{
        'device_connection': <String, dynamic>{
          'host': '10.0.0.7',
          'port': 502,
          'unit_id': 3,
        },
        'address_mode': 'zero_based',
        'local_topology_manifest_path': '',
        'local_topology_blob_path': '',
        'semantic_catalog_path': '',
        'poll_intervals': <String, dynamic>{
          'telemetry_ms': 5000,
          'diag_ms': 30000,
          'command_poll_ms': 500,
          'upload_poll_ms': 100,
        },
        'timeouts': <String, dynamic>{
          'connect_ms': 4000,
          'response_ms': 3000,
          'retry_backoff_ms': 100,
          'command_ms': 25000,
          'upload_chunk_ms': 3000,
          'upload_commit_ms': 15000,
        },
        'transport': <String, dynamic>{'retry_count': 1},
        'feature_flags': <String, dynamic>{
          'allow_telemetry_on_generation_mismatch': true,
          'show_unsupported_points': true,
          'pause_polling_during_write_workflows': true,
        },
      }),
    });

    final config = await ConfigStore().load();

    expect(config.pollIntervals.telemetryMs, 5000);
    expect(config.timeouts.responseMs, 3000);
    expect(config.transport.retryCount, 1);
  });

  test('lighting drafts round-trip through local store', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final store = ConfigStore();
    final drafts = <int, LightingScheduleDraft>{
      101: LightingScheduleDraft(
        moduleId: 101,
        zoneId: 1,
        slaveId: 3,
        relay1: const LightingRelayDraft(
          enabled: true,
          onHhmm: 630,
          offHhmm: 815,
          thresholdWm2: 120,
          dliLimit: 360,
        ),
        relay2: const LightingRelayDraft(
          enabled: true,
          onHhmm: 900,
          offHhmm: 1130,
          thresholdWm2: 480,
          dliLimit: 720,
        ),
        hysteresisSec: 4,
      ),
    };

    await store.saveLightingDrafts(drafts);
    final restored = await store.loadLightingDrafts();

    expect(restored.keys, contains(101));
    final draft = restored[101]!;
    expect(draft.moduleId, 101);
    expect(draft.zoneId, 1);
    expect(draft.slaveId, 3);
    expect(draft.relay1.enabled, isTrue);
    expect(draft.relay1.onHhmm, 630);
    expect(draft.relay1.offHhmm, 815);
    expect(draft.relay1.thresholdWm2, 120);
    expect(draft.relay1.dliLimit, 360);
    expect(draft.relay2.enabled, isTrue);
    expect(draft.relay2.onHhmm, 900);
    expect(draft.relay2.offHhmm, 1130);
    expect(draft.relay2.thresholdWm2, 480);
    expect(draft.relay2.dliLimit, 720);
    expect(draft.hysteresisSec, 4);
  });
}
