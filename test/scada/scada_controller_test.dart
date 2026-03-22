import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/scada/models/lighting_schedule_models.dart';
import 'package:greenhouse/scada/models/topology_models.dart';
import 'package:greenhouse/scada/models/scada_models.dart';
import 'package:greenhouse/scada/services/config_store.dart';
import 'package:greenhouse/scada/services/modbus_tcp_client.dart';
import 'package:greenhouse/scada/services/scada_controller.dart';
import 'package:greenhouse/scada/services/scada_logger.dart';
import 'package:greenhouse/scada/services/topology_store.dart';

void main() {
  group('ScadaController compatibility', () {
    test('ready when device metadata matches local topology', () async {
      final controller = ScadaController(
        client: _FakeModbusTcpClient(generation: 77),
        configStore: _FakeConfigStore(),
        logger: _FakeLogger(),
        topologyStore: _FakeTopologyStore(
          snapshot: _snapshot(
            manifest: _manifest(generation: 77, includeSchedule: true),
          ),
        ),
      );

      await controller.refreshSession();

      expect(controller.compatibility.state, ScadaCompatibilityState.ready);
      expect(controller.scheduleDisabledReasonForModule(101), isNull);
    });

    test(
      'generation mismatch blocks commands but keeps topology loaded',
      () async {
        final controller = ScadaController(
          client: _FakeModbusTcpClient(generation: 88),
          configStore: _FakeConfigStore(),
          logger: _FakeLogger(),
          topologyStore: _FakeTopologyStore(
            snapshot: _snapshot(
              manifest: _manifest(generation: 77, includeSchedule: true),
            ),
          ),
        );

        await controller.refreshSession();

        expect(
          controller.compatibility.state,
          ScadaCompatibilityState.topologyGenerationMismatch,
        );
        expect(
          controller.scheduleDisabledReasonForModule(101),
          contains('Topology mismatch'),
        );
      },
    );

    test(
      'missing schedule contract is exposed as command contract missing',
      () async {
        final controller = ScadaController(
          client: _FakeModbusTcpClient(generation: 77),
          configStore: _FakeConfigStore(),
          logger: _FakeLogger(),
          topologyStore: _FakeTopologyStore(
            snapshot: _snapshot(
              manifest: _manifest(generation: 77, includeSchedule: false),
            ),
          ),
        );

        await controller.refreshSession();

        expect(controller.compatibility.state, ScadaCompatibilityState.ready);
        expect(
          controller.scheduleDisabledReasonForModule(101),
          'Schedule command profile is absent for this module.',
        );
      },
    );

    test(
      'bootstrap timeout does not overwrite local topology state as map incompatible',
      () async {
        final controller = ScadaController(
          client: _TimeoutModbusTcpClient(),
          configStore: _FakeConfigStore(),
          logger: _FakeLogger(),
          topologyStore: _FakeTopologyStore(
            snapshot: const TopologyStoreSnapshot(
              manifest: null,
              blob: null,
              blobCrc32: null,
              manifestError: null,
              blobError: null,
              semanticCatalogPath: null,
              semanticCatalogError: null,
            ),
          ),
        );

        await controller.refreshSession();

        expect(
          controller.compatibility.state,
          ScadaCompatibilityState.localTopologyMissing,
        );
        expect(controller.lastError, contains('response timeout'));
      },
    );

    test(
      'runtime telemetry groups are exposed when local topology is missing',
      () async {
        final controller = ScadaController(
          client: _RuntimeTelemetryModbusTcpClient(),
          configStore: _FakeConfigStore(),
          logger: _FakeLogger(),
          topologyStore: _FakeTopologyStore(
            snapshot: const TopologyStoreSnapshot(
              manifest: null,
              blob: null,
              blobCrc32: null,
              manifestError: null,
              blobError: null,
              semanticCatalogPath: null,
              semanticCatalogError: null,
            ),
          ),
        );

        await controller.init();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          controller.compatibility.state,
          ScadaCompatibilityState.localTopologyMissing,
        );
        expect(
          controller.runtimeTelemetryModules.map((item) => item.moduleId),
          orderedEquals(const <int>[101, 201]),
        );

        controller.dispose();
      },
    );

    test(
      'polling splits slave status reads that exceed Modbus 125-register limit',
      () async {
        final client = _ChunkTrackingModbusTcpClient(generation: 77);
        final controller = ScadaController(
          client: client,
          configStore: _FakeConfigStore(),
          logger: _FakeLogger(),
          topologyStore: _FakeTopologyStore(
            snapshot: _snapshot(
              manifest: _manifestManySlaves(
                generation: 77,
                slaveIds: List<int>.generate(16, (index) => index + 1),
              ),
            ),
          ),
        );

        await controller.init();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(controller.lastError, isNull);
        expect(client.calls, contains('1080:120'));
        expect(client.calls, contains('1200:8'));

        controller.dispose();
      },
    );

    test(
      'polling reads only configured slave status ranges',
      () async {
        final client = _ChunkTrackingModbusTcpClient(generation: 77);
        final controller = ScadaController(
          client: client,
          configStore: _FakeConfigStore(),
          logger: _FakeLogger(),
          topologyStore: _FakeTopologyStore(
            snapshot: _snapshot(
              manifest: _manifestManySlaves(
                generation: 77,
                slaveIds: const <int>[1, 20],
              ),
            ),
          ),
        );

        await controller.init();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(controller.lastError, isNull);
        expect(client.calls, contains('1080:8'));
        expect(client.calls, contains('1232:8'));
        expect(client.calls, isNot(contains('1088:120')));

        controller.dispose();
      },
    );

    test(
      'polling does not refresh bootstrap on every telemetry tick',
      () async {
        final client = _ChunkTrackingModbusTcpClient(generation: 77);
        final controller = ScadaController(
          client: client,
          configStore: _FakeConfigStore(
            config: ScadaConfig.defaults().copyWith(
              pollIntervals: const PollIntervalsConfig(
                telemetryMs: 10,
                diagMs: 60000,
                commandPollMs: 500,
                uploadPollMs: 100,
              ),
            ),
          ),
          logger: _FakeLogger(),
          topologyStore: _FakeTopologyStore(
            snapshot: _snapshot(
              manifest: _manifest(generation: 77, includeSchedule: true),
            ),
          ),
        );

        await controller.init();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(client.calls.where((call) => call == '1264:32').length, 1);
        expect(client.calls.where((call) => call == '1408:10').length, 1);

        controller.dispose();
      },
    );

    test('diagnostics timeout aborts the current poll cycle', () async {
      final client = _DiagTimeoutAbortClient();
      final controller = ScadaController(
        client: client,
        configStore: _FakeConfigStore(
          config: ScadaConfig.defaults().copyWith(
            pollIntervals: const PollIntervalsConfig(
              telemetryMs: 10,
              diagMs: 10,
              commandPollMs: 500,
              uploadPollMs: 100,
            ),
          ),
        ),
        logger: _FakeLogger(),
        topologyStore: _FakeTopologyStore(
          snapshot: _snapshot(
            manifest: _manifest(generation: 77, includeSchedule: true),
          ),
        ),
      );

      await controller.init();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(client.diagReadCount, greaterThan(0));
      expect(client.sawTelemetryRead, isFalse);

      controller.dispose();
    });

    test('rtc set pauses background polling during workflow', () async {
      final client = _RtcOverlapDetectingClient();
      final controller = ScadaController(
        client: client,
        configStore: _FakeConfigStore(
          config: ScadaConfig.defaults().copyWith(
            pollIntervals: const PollIntervalsConfig(
              telemetryMs: 10,
              diagMs: 1000,
              commandPollMs: 10,
              uploadPollMs: 100,
            ),
            featureFlags: const FeatureFlagsConfig(
              allowTelemetryOnGenerationMismatch: true,
              showUnsupportedPoints: true,
              pausePollingDuringWriteWorkflows: true,
            ),
          ),
        ),
        logger: _FakeLogger(),
        topologyStore: _FakeTopologyStore(
          snapshot: _snapshot(
            manifest: _manifest(generation: 77, includeSchedule: true),
          ),
        ),
      );

      await controller.init();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await controller.setServerRtcTime(hour: 12, minute: 34);

      expect(client.sawOverlap, isFalse);

      controller.dispose();
    });

    test('schedule apply treats queued as in-progress until applied', () async {
      final client = _QueuedScheduleClient();
      final controller = ScadaController(
        client: client,
        configStore: _FakeConfigStore(
          config: ScadaConfig.defaults().copyWith(
            pollIntervals: const PollIntervalsConfig(
              telemetryMs: 60000,
              diagMs: 60000,
              commandPollMs: 50,
              uploadPollMs: 100,
            ),
          ),
        ),
        logger: _FakeLogger(),
        topologyStore: _FakeTopologyStore(
          snapshot: _snapshot(
            manifest: _manifest(
              generation: 77,
              includeSchedule: true,
              scheduleTimeoutMs: 300,
            ),
          ),
        ),
      );

      await controller.init();
      await controller.sendScheduleForModule(101);

      final status = controller.lightingStatusForModule(101);
      expect(status.phase, LightingSchedulePhase.success);
      expect(status.lastAppliedTrigger, status.trigger);
      expect(status.lastResult, 2);
      expect(status.message, 'Applied');

      controller.dispose();
    });

    test('schedule apply reports failure only after overall deadline', () async {
      final client = _RejectedScheduleClient();
      final controller = ScadaController(
        client: client,
        configStore: _FakeConfigStore(
          config: ScadaConfig.defaults().copyWith(
            pollIntervals: const PollIntervalsConfig(
              telemetryMs: 60000,
              diagMs: 60000,
              commandPollMs: 50,
              uploadPollMs: 100,
            ),
          ),
        ),
        logger: _FakeLogger(),
        topologyStore: _FakeTopologyStore(
          snapshot: _snapshot(
            manifest: _manifest(
              generation: 77,
              includeSchedule: true,
              scheduleTimeoutMs: 300,
            ),
          ),
        ),
      );

      await controller.init();
      final stopwatch = Stopwatch()..start();
      await controller.sendScheduleForModule(101);
      stopwatch.stop();

      final status = controller.lightingStatusForModule(101);
      expect(status.phase, LightingSchedulePhase.failed);
      expect(status.lastAppliedTrigger, status.trigger);
      expect(status.lastResult, 1304);
      expect(status.message, contains('invalid schedule'));
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(1800));

      controller.dispose();
    });

    test('restores last sent lighting draft after client restart', () async {
      final store = _FakeConfigStore(
        config: ScadaConfig.defaults().copyWith(
          pollIntervals: const PollIntervalsConfig(
            telemetryMs: 60000,
            diagMs: 60000,
            commandPollMs: 50,
            uploadPollMs: 100,
          ),
        ),
      );
      final firstController = ScadaController(
        client: _QueuedScheduleClient(),
        configStore: store,
        logger: _FakeLogger(),
        topologyStore: _FakeTopologyStore(
          snapshot: _snapshot(
            manifest: _manifest(generation: 77, includeSchedule: true),
          ),
        ),
      );

      await firstController.init();
      firstController.updateLightingDraft(101, (current) {
        return current.copyWith(
          slots: <LightingScheduleSlot>[
            const LightingScheduleSlot(
              enabled: true,
              onHhmm: 615,
              offHhmm: 745,
            ),
            const LightingScheduleSlot(
              enabled: false,
              onHhmm: 0,
              offHhmm: 0,
            ),
            const LightingScheduleSlot(
              enabled: true,
              onHhmm: 1800,
              offHhmm: 2230,
            ),
            const LightingScheduleSlot(
              enabled: false,
              onHhmm: 0,
              offHhmm: 0,
            ),
          ],
          applyValue: 2,
          expectedActiveCtrlVersion: 77,
          strictVersion: true,
        );
      });
      await firstController.sendScheduleForModule(101);
      expect(store.lightingDrafts.keys, contains(101));
      firstController.dispose();

      final secondController = ScadaController(
        client: _FakeModbusTcpClient(generation: 77),
        configStore: store,
        logger: _FakeLogger(),
        topologyStore: _FakeTopologyStore(
          snapshot: _snapshot(
            manifest: _manifest(generation: 77, includeSchedule: true),
          ),
        ),
      );

      await secondController.init();

      final restored = secondController.lightingStatusForModule(101);
      expect(restored.phase, LightingSchedulePhase.idle);
      expect(restored.draft.moduleId, 101);
      expect(restored.draft.zoneId, 1);
      expect(restored.draft.slaveId, 1);
      expect(restored.draft.slots[0].enabled, isTrue);
      expect(restored.draft.slots[0].onHhmm, 615);
      expect(restored.draft.slots[0].offHhmm, 745);
      expect(restored.draft.slots[2].enabled, isTrue);
      expect(restored.draft.slots[2].onHhmm, 1800);
      expect(restored.draft.slots[2].offHhmm, 2230);
      expect(restored.draft.applyValue, 2);
      expect(restored.draft.expectedActiveCtrlVersion, 77);
      expect(restored.draft.strictVersion, isTrue);

      secondController.dispose();
    });
  });
}

TopologyStoreSnapshot _snapshot({required TopologyManifest manifest}) {
  return TopologyStoreSnapshot(
    manifest: manifest,
    blob: Uint8List.fromList(const <int>[0x54, 0x4F, 0x50, 0x32]),
    blobCrc32: 0,
    manifestError: null,
    blobError: null,
    semanticCatalogPath: null,
    semanticCatalogError: null,
  );
}

TopologyManifest _manifest({
  required int generation,
  required bool includeSchedule,
  int scheduleTimeoutMs = 3000,
}) {
  return TopologyManifest.fromJson(<String, dynamic>{
    'schema_version': '2.0',
    'generation': generation,
    'topology_id': 1,
    'modules': <Map<String, dynamic>>[
      <String, dynamic>{
        'module_id': 101,
        'module_type': 1,
        'bus_type': 1,
        'bus_index': 0,
        'slave_id': 1,
        'zone_id': 1,
        'capability_mask': 0,
        'user_param0': 0,
        'user_param1': 0,
      },
      <String, dynamic>{
        'module_id': 201,
        'module_type': 2,
        'bus_type': 1,
        'bus_index': 0,
        'slave_id': 2,
        'zone_id': 0xFFFF,
        'capability_mask': 0,
        'user_param0': 0,
        'user_param1': 0,
      },
    ],
    'requests': const <Map<String, dynamic>>[],
    'points': <Map<String, dynamic>>[
      <String, dynamic>{
        'point_id': 1,
        'module_id': 201,
        'req_id': 1,
        'point_type': 5,
        'scale_pow10': 0,
        'publish_index': 0,
        'quality_policy': 1,
        'stale_timeout_s': 10,
        'alarm_low': 0,
        'alarm_high': 0,
        'semantic_name': 'outside_temperature',
      },
    ],
    'commands': includeSchedule
        ? <Map<String, dynamic>>[
            <String, dynamic>{
              'cmd_id': 501,
              'module_id': 101,
              'fc': 16,
              'start_reg': 110,
              'max_reg_count': 12,
              'payload_offset': 0,
              'timeout_ms': scheduleTimeoutMs,
              'ack_point_id': 0,
              'cmd_kind': 'schedule',
            },
            <String, dynamic>{
              'cmd_id': 502,
              'module_id': 101,
              'fc': 6,
              'start_reg': 122,
              'max_reg_count': 1,
              'payload_offset': 12,
              'timeout_ms': scheduleTimeoutMs,
              'ack_point_id': 0,
              'cmd_kind': 'schedule',
            },
          ]
        : const <Map<String, dynamic>>[],
    'policies': const <Map<String, dynamic>>[],
  });
}

TopologyManifest _manifestManySlaves({
  required int generation,
  required List<int> slaveIds,
}) {
  return TopologyManifest.fromJson(<String, dynamic>{
    'schema_version': '2.0',
    'generation': generation,
    'topology_id': 1,
    'modules': slaveIds
        .map(
          (slaveId) => <String, dynamic>{
            'module_id': 100 + slaveId,
            'module_type': 1,
            'bus_type': 1,
            'bus_index': slaveId - 1,
            'slave_id': slaveId,
            'zone_id': slaveId,
            'capability_mask': 0,
            'user_param0': 0,
            'user_param1': 0,
          },
        )
        .toList(growable: false),
    'requests': const <Map<String, dynamic>>[],
    'points': const <Map<String, dynamic>>[
      <String, dynamic>{
        'point_id': 1,
        'module_id': 101,
        'req_id': 1,
        'point_type': 5,
        'scale_pow10': 0,
        'publish_index': 0,
        'quality_policy': 1,
        'stale_timeout_s': 10,
        'alarm_low': 0,
        'alarm_high': 0,
        'semantic_name': 'outside_temperature',
      },
    ],
    'commands': const <Map<String, dynamic>>[],
    'policies': const <Map<String, dynamic>>[],
  });
}

class _FakeTopologyStore extends TopologyStore {
  _FakeTopologyStore({required this.snapshot});

  final TopologyStoreSnapshot snapshot;

  @override
  Future<TopologyStoreSnapshot> load({
    required String manifestPath,
    required String blobPath,
    required String semanticCatalogPath,
  }) async {
    return snapshot;
  }
}

class _FakeConfigStore extends ConfigStore {
  _FakeConfigStore({
    this.config,
    Map<int, LightingScheduleDraft>? lightingDrafts,
  }) : _lightingDrafts = Map<int, LightingScheduleDraft>.from(
         lightingDrafts ?? const <int, LightingScheduleDraft>{},
       );

  final ScadaConfig? config;
  final Map<int, LightingScheduleDraft> _lightingDrafts;

  Map<int, LightingScheduleDraft> get lightingDrafts =>
      Map<int, LightingScheduleDraft>.unmodifiable(_lightingDrafts);

  @override
  Future<ScadaConfig> load() async => config ?? ScadaConfig.defaults();

  @override
  Future<void> save(ScadaConfig config) async {}

  @override
  Future<Map<int, LightingScheduleDraft>> loadLightingDrafts() async {
    return Map<int, LightingScheduleDraft>.from(_lightingDrafts);
  }

  @override
  Future<void> saveLightingDrafts(Map<int, LightingScheduleDraft> drafts) async {
    _lightingDrafts
      ..clear()
      ..addAll(drafts);
  }
}

class _FakeLogger extends ScadaLogger {
  @override
  Future<void> init() async {}

  @override
  Future<void> logClientEvent(String event) async {}

  @override
  Future<void> logScheduleTransaction({
    required int moduleId,
    required int slaveId,
    required String event,
    required String operation,
    int? address,
    int? count,
    List<int>? requestRegs,
    List<int>? responseRegs,
    int? trigger,
    int? lastAppliedTrigger,
    int? lastResult,
    int? lastIoErr,
    String? message,
  }) async {}
}

class _FakeModbusTcpClient extends ModbusTcpClient {
  _FakeModbusTcpClient({required this.generation});

  final int generation;
  final StreamController<bool> _stream = StreamController<bool>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connection => _stream.stream;

  @override
  Future<void> connect(String host, int port) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<int>> readHoldingRegisters({
    required int unitId,
    required int startAddress,
    required int count,
  }) async {
    if (startAddress == 1264) {
      final regs = List<int>.filled(32, 0);
      regs[0] = 4;
      regs[1] = 0x0003;
      regs[4] = 1;
      regs[5] = 6;
      regs[6] = 0;
      regs[7] = 1080;
      regs[8] = 1240;
      regs[11] = 180;
      regs[12] = 24;
      regs[13] = 8;
      return regs.sublist(0, count);
    }
    if (startAddress == 1408) {
      return <int>[
        0,
        0,
        0,
        0x0001,
        2,
        0,
        (generation >> 16) & 0xFFFF,
        generation & 0xFFFF,
        0,
        4,
      ].sublist(0, count);
    }
    return List<int>.filled(count, 0);
  }

  @override
  Future<void> writeSingleRegister({
    required int unitId,
    required int address,
    required int value,
  }) async {}

  @override
  Future<void> writeMultipleRegisters({
    required int unitId,
    required int startAddress,
    required List<int> values,
  }) async {}

  @override
  Future<void> dispose() async {
    await _stream.close();
  }
}

class _RuntimeTelemetryModbusTcpClient extends ModbusTcpClient {
  final StreamController<bool> _stream = StreamController<bool>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connection => _stream.stream;

  @override
  Future<void> connect(String host, int port) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<int>> readHoldingRegisters({
    required int unitId,
    required int startAddress,
    required int count,
  }) async {
    if (startAddress == 1264) {
      final regs = List<int>.filled(32, 0);
      regs[0] = 4;
      regs[1] = 0x0003;
      regs[4] = 4;
      regs[5] = 6;
      regs[6] = 0;
      regs[7] = 1080;
      regs[8] = 1240;
      regs[11] = 180;
      regs[12] = 24;
      regs[13] = 8;
      regs[14] = 10;
      regs[15] = 7;
      return regs.sublist(0, count);
    }
    if (startAddress == 1408) {
      return <int>[0, 0, 0, 0x0001, 2, 0, 0, 8, 0, 444].sublist(0, count);
    }
    if (startAddress == 0) {
      final rows = <List<int>>[
        _pointRow(value: 24.5, quality: 0, ageSec: 1, moduleId: 101, flags: 1),
        _pointRow(value: 61.2, quality: 0, ageSec: 1, moduleId: 101, flags: 1),
        _pointRow(value: 11.3, quality: 0, ageSec: 1, moduleId: 201, flags: 1),
        _pointRow(value: 4.6, quality: 0, ageSec: 1, moduleId: 201, flags: 1),
      ];
      return rows.expand((row) => row).take(count).toList(growable: false);
    }
    return List<int>.filled(count, 0);
  }

  @override
  Future<void> writeSingleRegister({
    required int unitId,
    required int address,
    required int value,
  }) async {}

  @override
  Future<void> writeMultipleRegisters({
    required int unitId,
    required int startAddress,
    required List<int> values,
  }) async {}

  @override
  Future<void> dispose() async {
    await _stream.close();
  }
}

class _TimeoutModbusTcpClient extends ModbusTcpClient {
  final StreamController<bool> _stream = StreamController<bool>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connection => _stream.stream;

  @override
  Future<void> connect(String host, int port) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<int>> readHoldingRegisters({
    required int unitId,
    required int startAddress,
    required int count,
  }) async {
    throw ModbusTcpException('response timeout (1 consecutive)');
  }

  @override
  Future<void> writeSingleRegister({
    required int unitId,
    required int address,
    required int value,
  }) async {}

  @override
  Future<void> writeMultipleRegisters({
    required int unitId,
    required int startAddress,
    required List<int> values,
  }) async {}

  @override
  Future<void> dispose() async {
    await _stream.close();
  }
}

class _ChunkTrackingModbusTcpClient extends ModbusTcpClient {
  _ChunkTrackingModbusTcpClient({required this.generation});

  final int generation;
  final StreamController<bool> _stream = StreamController<bool>.broadcast();
  final List<String> calls = <String>[];

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connection => _stream.stream;

  @override
  Future<void> connect(String host, int port) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<int>> readHoldingRegisters({
    required int unitId,
    required int startAddress,
    required int count,
  }) async {
    calls.add('$startAddress:$count');
    if (count > 125) {
      throw ModbusTcpException('read count must be between 1 and 125');
    }
    if (startAddress == 1264) {
      final regs = List<int>.filled(32, 0);
      regs[0] = 4;
      regs[1] = 0x0003;
      regs[4] = 1;
      regs[5] = 6;
      regs[6] = 0;
      regs[7] = 1080;
      regs[8] = 1240;
      regs[11] = 180;
      regs[12] = 24;
      regs[13] = 8;
      regs[14] = 13;
      regs[15] = 2;
      return regs.sublist(0, count);
    }
    if (startAddress == 1408) {
      return <int>[
        0,
        0,
        0,
        0x0001,
        2,
        0,
        (generation >> 16) & 0xFFFF,
        generation & 0xFFFF,
        0,
        540,
      ].sublist(0, count);
    }
    if (startAddress == 0) {
      return _pointRow(
        value: 24.5,
        quality: 0,
        ageSec: 1,
        moduleId: 101,
        flags: 1,
      ).sublist(0, count);
    }
    if (startAddress >= 1080 && startAddress < 1208) {
      return List<int>.filled(count, 0);
    }
    if (startAddress == 1278) {
      return <int>[13, 2].sublist(0, count);
    }
    return List<int>.filled(count, 0);
  }

  @override
  Future<void> writeSingleRegister({
    required int unitId,
    required int address,
    required int value,
  }) async {}

  @override
  Future<void> writeMultipleRegisters({
    required int unitId,
    required int startAddress,
    required List<int> values,
  }) async {}

  @override
  Future<void> dispose() async {
    await _stream.close();
  }
}

class _RtcOverlapDetectingClient extends ModbusTcpClient {
  final StreamController<bool> _stream = StreamController<bool>.broadcast();
  bool rtcWorkflowActive = false;
  bool sawOverlap = false;
  int _rtcStateReads = 0;
  int _lastRtcToken = 0;

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connection => _stream.stream;

  @override
  Future<void> connect(String host, int port) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<int>> readHoldingRegisters({
    required int unitId,
    required int startAddress,
    required int count,
  }) async {
    if (rtcWorkflowActive && (startAddress == 0 || startAddress == 1278)) {
      sawOverlap = true;
    }
    if (startAddress == 1264) {
      final regs = List<int>.filled(32, 0);
      regs[0] = 4;
      regs[1] = 0x0003;
      regs[4] = 1;
      regs[5] = 6;
      regs[6] = 0;
      regs[7] = 1080;
      regs[8] = 1240;
      regs[11] = 180;
      regs[12] = 24;
      regs[13] = 8;
      regs[14] = 10;
      regs[15] = 30;
      return regs.sublist(0, count);
    }
    if (startAddress == 1408) {
      return <int>[0, 0, 0, 0x0001, 2, 0, 0, 77, 0, 540].sublist(0, count);
    }
    if (startAddress == 0) {
      return _pointRow(
        value: 24.5,
        quality: 0,
        ageSec: 1,
        moduleId: 101,
        flags: 1,
      ).sublist(0, count);
    }
    if (startAddress == 1080) {
      return List<int>.filled(count, 0);
    }
    if (startAddress == 1278) {
      return <int>[10, 30].sublist(0, count);
    }
    if (startAddress == 1283) {
      _rtcStateReads += 1;
      if (_rtcStateReads == 1 && count == 1) {
        return const <int>[0];
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
      rtcWorkflowActive = false;
      return <int>[_lastRtcToken, 2].sublist(0, count);
    }
    if (startAddress == 1376) {
      return List<int>.filled(count, 0);
    }
    return List<int>.filled(count, 0);
  }

  @override
  Future<void> writeSingleRegister({
    required int unitId,
    required int address,
    required int value,
  }) async {}

  @override
  Future<void> writeMultipleRegisters({
    required int unitId,
    required int startAddress,
    required List<int> values,
  }) async {
    if (startAddress == 1280) {
      rtcWorkflowActive = true;
      if (values.length >= 3) {
        _lastRtcToken = values[2] & 0xFFFF;
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _stream.close();
  }
}

class _DiagTimeoutAbortClient extends ModbusTcpClient {
  final StreamController<bool> _stream = StreamController<bool>.broadcast();
  int diagReadCount = 0;
  bool sawTelemetryRead = false;

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connection => _stream.stream;

  @override
  Future<void> connect(String host, int port) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<int>> readHoldingRegisters({
    required int unitId,
    required int startAddress,
    required int count,
  }) async {
    if (startAddress == 1264) {
      final regs = List<int>.filled(32, 0);
      regs[0] = 4;
      regs[1] = 0x0003;
      regs[4] = 1;
      regs[5] = 6;
      regs[6] = 0;
      regs[7] = 1080;
      regs[8] = 1240;
      regs[11] = 180;
      regs[12] = 24;
      regs[13] = 8;
      regs[14] = 10;
      regs[15] = 30;
      return regs.sublist(0, count);
    }
    if (startAddress == 1408) {
      return <int>[0, 0, 0, 0x0001, 2, 0, 0, 77, 0, 540].sublist(0, count);
    }
    if (startAddress == 1278) {
      return <int>[10, 30].sublist(0, count);
    }
    if (startAddress == 1376) {
      diagReadCount += 1;
      throw ModbusTcpException('response timeout (1 consecutive)');
    }
    if (startAddress == 0 || startAddress == 1080) {
      sawTelemetryRead = true;
    }
    return List<int>.filled(count, 0);
  }

  @override
  Future<void> writeSingleRegister({
    required int unitId,
    required int address,
    required int value,
  }) async {}

  @override
  Future<void> writeMultipleRegisters({
    required int unitId,
    required int startAddress,
    required List<int> values,
  }) async {}

  @override
  Future<void> dispose() async {
    await _stream.close();
  }
}

class _QueuedScheduleClient extends _ScheduleApplyClientBase {
  @override
  List<int> commandStateForTrigger(int trigger) {
    final startedAt = triggerWrittenAt;
    if (startedAt == null) {
      return const <int>[0, 0, 0];
    }
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    if (elapsedMs < 700) {
      return <int>[trigger, 1, 0];
    }
    return <int>[trigger, 2, 0];
  }
}

class _RejectedScheduleClient extends _ScheduleApplyClientBase {
  @override
  List<int> commandStateForTrigger(int trigger) => <int>[trigger, 1304, 0];
}

abstract class _ScheduleApplyClientBase extends _FakeModbusTcpClient {
  _ScheduleApplyClientBase() : super(generation: 77);

  int currentTrigger = 0;
  DateTime? triggerWrittenAt;

  List<int> commandStateForTrigger(int trigger);

  @override
  Future<List<int>> readHoldingRegisters({
    required int unitId,
    required int startAddress,
    required int count,
  }) async {
    if (startAddress == 1240) {
      final regs = List<int>.filled(24, 0);
      if (count > 21) {
        regs[21] = 0;
      }
      return regs.sublist(0, count);
    }
    if (startAddress == 1261) {
      return commandStateForTrigger(currentTrigger).sublist(0, count);
    }
    return super.readHoldingRegisters(
      unitId: unitId,
      startAddress: startAddress,
      count: count,
    );
  }

  @override
  Future<void> writeSingleRegister({
    required int unitId,
    required int address,
    required int value,
  }) async {
    if (address == 1260) {
      currentTrigger = value & 0xFFFF;
      triggerWrittenAt = DateTime.now();
    }
  }

  @override
  Future<void> writeMultipleRegisters({
    required int unitId,
    required int startAddress,
    required List<int> values,
  }) async {}
}

List<int> _pointRow({
  required double value,
  required int quality,
  required int ageSec,
  required int moduleId,
  required int flags,
}) {
  final data = ByteData(4)..setFloat32(0, value, Endian.big);
  return <int>[
    data.getUint16(0, Endian.big),
    data.getUint16(2, Endian.big),
    quality,
    ageSec,
    moduleId,
    flags,
  ];
}
