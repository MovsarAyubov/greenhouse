import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/scada/models/lighting_schedule_models.dart';
import 'package:greenhouse/scada/models/topology_models.dart';
import 'package:greenhouse/scada/services/command_builder.dart';
import 'package:greenhouse/scada/services/modbus_tcp_client.dart';
import 'package:greenhouse/scada/services/register_map.dart';
import 'package:greenhouse/scada/services/topology_resolver.dart';
import 'package:greenhouse/scada/services/topology_store.dart';
import 'package:greenhouse/scada/services/topology_uploader.dart';

void main() {
  test('schedule command builder uses lighting setpoints payload shape', () {
    final module = TopologyModule.fromJson(<String, dynamic>{
      'module_id': 101,
      'module_type': 1,
      'bus_type': 1,
      'bus_index': 0,
      'slave_id': 1,
      'zone_id': 1,
      'capability_mask': 0,
      'user_param0': 0,
      'user_param1': 0,
    });
    final contract = ScheduleCommandContract(
      cmdProfileId: 5001,
      timeoutMs: 3000,
    );
    final draft = LightingScheduleDraft(
      moduleId: 101,
      zoneId: 1,
      slaveId: 1,
      relay1: const LightingRelayDraft(
        enabled: true,
        onHhmm: 600,
        offHhmm: 900,
        thresholdWm2: 120,
        dliLimit: 360,
      ),
      relay2: const LightingRelayDraft(
        enabled: false,
        onHhmm: 0,
        offHhmm: 0,
        thresholdWm2: 0,
        dliLimit: 0,
      ),
      hysteresisSec: 9,
    );

    final request = const CommandBuilder().buildScheduleCommand(
      module: module,
      contract: contract,
      draft: draft,
    );

    expect(request.targetSlaveId, 1);
    expect(request.targetModuleId, 101);
    expect(request.cmdProfileId, 5001);
    expect(
      request.payload,
      orderedEquals(const <int>[
        1,
        600,
        900,
        120,
        0,
        360,
        0,
        0,
        0,
        0,
        0,
        0,
        9,
      ]),
    );
  });

  test('topology uploader sets reset and commit on single chunk', () {
    final uploader = TopologyUploader(
      client: _NoopClient(),
      registerMap: _TestRegisterMap(),
    );

    final chunks = uploader.buildChunks(
      blob: Uint8List.fromList(const <int>[0xAA, 0x55, 0x12, 0x34]),
      generation: 1,
      startToken: 100,
    );

    expect(chunks, hasLength(1));
    expect(chunks.first.flags, TopologyUploader.resetFlag | TopologyUploader.commitFlag);
    expect(chunks.first.chunkWords, 2);
    expect(chunks.first.chunkDataWords, <int>[0xAA55, 0x1234]);
  });

  test('topology store enriches manifest from sidecar semantic catalog', () async {
    final tempDir = await Directory.systemTemp.createTemp('scada_topology_test_');
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final manifestFile = File('${tempDir.path}${Platform.pathSeparator}one_zone_one_weather_topology.json');
    await manifestFile.writeAsString(
      jsonEncode(<String, dynamic>{
        'ver_minor': 0,
        'generation': 101,
        'topology_id': 1001,
        'modules': <Map<String, dynamic>>[
          <String, dynamic>{
            'module_id': 201,
            'module_type': 2,
            'bus_type': 1,
            'bus_index': 0,
            'slave_id': 20,
            'zone_id': 65535,
            'capability_mask': 0,
            'user_param0': 0,
            'user_param1': 0,
          },
        ],
        'requests': const <Map<String, dynamic>>[],
        'points': <Map<String, dynamic>>[
          <String, dynamic>{
            'point_id': 20100,
            'module_id': 201,
            'req_id': 2010,
            'point_type': 2,
            'scale_pow10': -1,
            'publish_index': 9,
            'quality_policy': 1,
            'stale_timeout_s': 30,
            'alarm_low': -500,
            'alarm_high': 600,
          },
        ],
        'commands': const <Map<String, dynamic>>[],
        'policies': const <Map<String, dynamic>>[],
      }),
    );

    final semanticFile = File('${tempDir.path}${Platform.pathSeparator}one_zone_one_weather_semantics.json');
    await semanticFile.writeAsString(
      jsonEncode(<String, dynamic>{
        'schema': 'scada_semantic_mapping_v1',
        'points': <String, dynamic>{
          'weather_1.out_temp': <String, dynamic>{
            'module_id': 201,
            'point_id': 20100,
            'publish_index': 9,
            'label': 'Outdoor temperature',
          },
        },
      }),
    );

    final snapshot = await TopologyStore().load(
      manifestPath: '"${manifestFile.path}"',
      blobPath: '',
      semanticCatalogPath: '',
    );

    expect(snapshot.manifestError, isNull);
    expect(snapshot.hasSemanticCatalog, isTrue);
    expect(snapshot.semanticCatalogPath, semanticFile.path);
    expect(snapshot.manifest, isNotNull);
    final point = snapshot.manifest!.points.single;
    expect(point.semanticName, 'outside_temperature');
    expect(point.displayName, 'Outdoor temperature');
  });
}

class _NoopClient extends _BaseNoopClient {}

class _TestRegisterMap extends _BaseRegisterMap {}

class _BaseNoopClient extends _BaseClient {}

class _BaseClient extends _BaseModbusClient {}

class _BaseModbusClient extends ModbusTcpClient {
  @override
  Future<List<int>> readHoldingRegisters({
    required int unitId,
    required int startAddress,
    required int count,
  }) async => List<int>.filled(count, 0);

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
}

class _BaseRegisterMap extends RegisterMap {
  const _BaseRegisterMap();
}
