import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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

    test('generation mismatch blocks commands but keeps topology loaded', () async {
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
    });

    test('missing schedule contract is exposed as command contract missing', () async {
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
    });

    test('bootstrap timeout does not overwrite local topology state as map incompatible', () async {
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
    });

    test('runtime telemetry groups are exposed when local topology is missing', () async {
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
              'timeout_ms': 3000,
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
              'timeout_ms': 3000,
              'ack_point_id': 0,
              'cmd_kind': 'schedule',
            },
          ]
        : const <Map<String, dynamic>>[],
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
  @override
  Future<ScadaConfig> load() async => ScadaConfig.defaults();

  @override
  Future<void> save(ScadaConfig config) async {}
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
      return <int>[
        0,
        0,
        0,
        0x0001,
        2,
        0,
        0,
        8,
        0,
        444,
      ].sublist(0, count);
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
