import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/scada/models/lighting_schedule_models.dart';
import 'package:greenhouse/scada/models/topology_models.dart';
import 'package:greenhouse/scada/models/scada_models.dart';
import 'package:greenhouse/scada/models/window_setpoint_models.dart';
import 'package:greenhouse/scada/services/config_store.dart';
import 'package:greenhouse/scada/services/modbus_tcp_client.dart';
import 'package:greenhouse/scada/services/scada_controller.dart';
import 'package:greenhouse/scada/services/scada_logger.dart';
import 'package:greenhouse/scada/services/topology_store.dart';

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: '');
  });

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

    test('unknown lighting profile is exposed as unsupported module', () async {
      final controller = ScadaController(
        client: _FakeModbusTcpClient(generation: 77),
        configStore: _FakeConfigStore(),
        logger: _FakeLogger(),
        topologyStore: _FakeTopologyStore(
          snapshot: _snapshot(
            manifest: _manifestUnknownLightingProfile(generation: 77),
          ),
        ),
      );

      await controller.refreshSession();

      expect(controller.compatibility.state, ScadaCompatibilityState.ready);
      expect(
        controller.scheduleDisabledReasonForModule(150),
        'Lighting setpoints profile is absent for this module.',
      );
    });

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

    test('polling reads only configured slave status ranges', () async {
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
    });

    test('polling avoids direct RTU reads from zone slaves', () async {
      final client = _WindowDebugRegisterClient(generation: 77);
      final controller = ScadaController(
        client: client,
        configStore: _FakeConfigStore(),
        logger: _FakeLogger(),
        topologyStore: _FakeTopologyStore(
          snapshot: _snapshot(
            manifest: _manifest(generation: 77, includeSchedule: true),
          ),
        ),
      );

      await controller.init();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final snapshot = controller.windowDebugRegisterForModule(101);
      expect(snapshot, isNull);
      expect(client.debugReads, 0);

      controller.dispose();
    });

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
      controller.updateLightingDraft(101, (current) {
        return current.copyWith(
          relay1: const LightingRelayDraft(
            enabled: true,
            onHhmm: 615,
            offHhmm: 2230,
            thresholdWm2: 120,
            dliLimit: 360,
          ),
          relay2: const LightingRelayDraft(
            enabled: true,
            onHhmm: 700,
            offHhmm: 2100,
            thresholdWm2: 400,
            dliLimit: 600,
          ),
          hysteresisSec: 4,
        );
      });
      await controller.sendScheduleForModule(101);

      final status = controller.lightingStatusForModule(101);
      expect(status.phase, LightingSchedulePhase.success);
      expect(status.lastAppliedTrigger, status.trigger);
      expect(status.lastResult, 2);
      expect(status.message, 'Applied');
      expect(
        client.writeOrder,
        orderedEquals(const <String>['payload', 'trigger']),
      );
      expect(client.lastPayloadStartAddress, 1240);
      expect(
        client.lastPayloadWrite,
        orderedEquals(const <int>[
          1,
          101,
          5001,
          13,
          1,
          615,
          2230,
          120,
          0,
          360,
          1,
          700,
          2100,
          400,
          0,
          600,
          4,
        ]),
      );
      expect(client.lastTriggerAddress, 1260);
      expect(client.currentTrigger, isNonZero);

      controller.dispose();
    });

    test(
      'schedule apply reports failure only after overall deadline',
      () async {
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
        expect(status.lastResult, 13);
        expect(status.message, contains('reject busy'));
        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(1800));

        controller.dispose();
      },
    );

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
          relay1: const LightingRelayDraft(
            enabled: true,
            onHhmm: 615,
            offHhmm: 2230,
            thresholdWm2: 125,
            dliLimit: 375,
          ),
          relay2: const LightingRelayDraft(
            enabled: false,
            onHhmm: 0,
            offHhmm: 0,
            thresholdWm2: 0,
            dliLimit: 0,
          ),
          hysteresisSec: 5,
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
      expect(restored.draft.relay1.enabled, isTrue);
      expect(restored.draft.relay1.onHhmm, 615);
      expect(restored.draft.relay1.offHhmm, 2230);
      expect(restored.draft.relay1.thresholdWm2, 125);
      expect(restored.draft.relay1.dliLimit, 375);
      expect(restored.draft.relay2.enabled, isFalse);
      expect(restored.draft.hysteresisSec, 5);

      secondController.dispose();
    });

    test('window setpoints are sent through master command ingress', () async {
      final client = _WindowSetpointWriteClient(generation: 77);
      final store = _FakeConfigStore();
      final controller = ScadaController(
        client: client,
        configStore: store,
        logger: _FakeLogger(),
        topologyStore: _FakeTopologyStore(
          snapshot: _snapshot(
            manifest: _manifest(generation: 77, includeSchedule: true),
          ),
        ),
      );

      await controller.init();
      controller.updateWindowSetpointDraft(
        101,
        (draft) => draft
            .copyWithValue(WindowSetpointRegister.posATarget, 250)
            .copyWithValue(WindowSetpointRegister.posBTarget, 500)
            .copyWithValue(WindowSetpointRegister.ctrlMode, 1)
            .copyWithValue(WindowSetpointRegister.tempSetpoint, 245)
            .copyWithValue(WindowSetpointRegister.humStep, 10)
            .copyWithValue(WindowSetpointRegister.rainWindwardPercent, 20)
            .copyWithValue(WindowSetpointRegister.tempStepMaxIndex, 3)
            .copyWithValue(WindowSetpointRegister.curtainManualTarget, 300)
            .copyWithValue(
              WindowSetpointRegister.curtainRadiationThreshold,
              450,
            )
            .copyWithValue(WindowSetpointRegister.curtainHumHighTarget, 700)
            .copyWithValue(WindowSetpointRegister.curtainFaultResetToken, 77)
            .copyWithValue(WindowSetpointRegister.airTempTarget, 230)
            .copyWithValue(WindowSetpointRegister.airHumTarget, 650),
      );

      await controller.sendWindowSetpointsForModule(101);

      expect(client.operations, hasLength(20));
      expect(
        client.operations.map((call) => call.startAddress),
        orderedEquals(const <int>[
          1240,
          1260,
          1240,
          1260,
          1240,
          1260,
          1240,
          1260,
          1240,
          1260,
          1240,
          1260,
          1240,
          1260,
          1240,
          1260,
          1240,
          1260,
          1240,
          1260,
        ]),
      );
      expect(client.operations.first.values, const <int>[
        1,
        101,
        5002,
        2,
        250,
        500,
      ]);
      expect(client.operations[1].singleValue, 1);
      expect(client.operations[2].values, const <int>[
        1,
        101,
        5004,
        16,
        1,
        0,
        245,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(client.operations[4].values, const <int>[
        1,
        101,
        5005,
        16,
        0,
        700,
        10,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(client.operations[6].values, const <int>[1, 101, 5006, 2, 20, 0]);
      expect(client.operations[8].values, const <int>[
        1,
        101,
        5007,
        6,
        0,
        3,
        0,
        0,
        60000,
        60,
      ]);
      expect(client.operations[10].values, const <int>[
        1,
        101,
        5015,
        8,
        0,
        300,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(client.operations[12].values, const <int>[
        1,
        101,
        5016,
        10,
        450,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(client.operations[14].values, const <int>[
        1,
        101,
        5017,
        6,
        0,
        0,
        0,
        0,
        0,
        700,
      ]);
      expect(client.operations[16].values, const <int>[1, 101, 5018, 1, 77]);
      expect(client.operations[18].values, const <int>[
        1,
        101,
        5019,
        2,
        230,
        650,
      ]);
      expect(
        client.operations
            .where((call) => call.singleValue != null)
            .map((call) => call.singleValue),
        orderedEquals(const <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      );
      expect(store.windowDrafts[101]?.valueFor(103), 250);
      expect(
        store.windowDrafts[101]?.valueFor(
          WindowSetpointRegister.windowAFaultResetToken,
        ),
        0,
      );
      expect(
        store.windowDrafts[101]?.valueFor(
          WindowSetpointRegister.curtainFaultResetToken,
        ),
        0,
      );
      expect(
        controller.windowSetpointStatusForModule(101).phase,
        WindowSetpointPhase.success,
      );

      controller.dispose();
    });

    test('window setpoints wait for each command trigger to apply', () async {
      final client = _DelayedWindowSetpointWriteClient(generation: 77);
      final controller = ScadaController(
        client: client,
        configStore: _FakeConfigStore(
          config: ScadaConfig.defaults().copyWith(
            timeouts: ScadaConfig.defaults().timeouts.copyWith(commandMs: 3000),
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
      controller.updateWindowSetpointDraft(101, _dirtyEveryWindowBlock);
      await controller.sendWindowSetpointsForModule(101);

      final payloadStarts = client.operations
          .where((call) => call.startAddress == 1240)
          .map((call) => call.values![2])
          .toList(growable: false);
      expect(payloadStarts, const <int>[
        5002,
        5004,
        5005,
        5006,
        5007,
        5015,
        5016,
        5017,
        5018,
        5019,
      ]);
      expect(client.pollReads, greaterThanOrEqualTo(20));

      controller.dispose();
    });

    test('zone 2 window setpoints use zone 2 command profiles', () async {
      final client = _WindowSetpointWriteClient(generation: 77);
      final controller = ScadaController(
        client: client,
        configStore: _FakeConfigStore(),
        logger: _FakeLogger(),
        topologyStore: _FakeTopologyStore(
          snapshot: _snapshot(
            manifest: _manifest(
              generation: 77,
              includeSchedule: true,
              includeZone2: true,
            ),
          ),
        ),
      );

      await controller.init();
      controller.updateWindowSetpointDraft(102, _dirtyEveryWindowBlock);
      await controller.sendWindowSetpointsForModule(102);

      final payloads = client.operations
          .where((call) => call.values != null)
          .map((call) => call.values!)
          .toList(growable: false);
      expect(
        payloads.map((values) => values[2]),
        orderedEquals(const <int>[
          5008,
          5009,
          5010,
          5011,
          5012,
          5020,
          5021,
          5022,
          5023,
          5024,
        ]),
      );
      expect(payloads.every((values) => values[0] == 2), isTrue);
      expect(payloads.every((values) => values[1] == 102), isTrue);

      controller.dispose();
    });

    test('window setpoints reject nonzero command ingress IO error', () async {
      final client = _IoErrWindowSetpointWriteClient(generation: 77);
      final controller = ScadaController(
        client: client,
        configStore: _FakeConfigStore(),
        logger: _FakeLogger(),
        topologyStore: _FakeTopologyStore(
          snapshot: _snapshot(
            manifest: _manifest(generation: 77, includeSchedule: true),
          ),
        ),
      );

      await controller.init();
      controller.updateWindowSetpointDraft(
        101,
        (draft) => draft.copyWithValue(WindowSetpointRegister.posATarget, 1),
      );
      await controller.sendWindowSetpointsForModule(101);

      final status = controller.windowSetpointStatusForModule(101);
      expect(status.phase, WindowSetpointPhase.failed);
      expect(status.message, contains('io=timeout'));

      controller.dispose();
    });

    test('window setpoints are auto-resynced after slave recovers', () async {
      final client = _RecoveringWindowSetpointClient(generation: 77);
      final store = _FakeConfigStore(
        config: ScadaConfig.defaults().copyWith(
          pollIntervals: const PollIntervalsConfig(
            telemetryMs: 10,
            diagMs: 60000,
            commandPollMs: 50,
            uploadPollMs: 100,
          ),
        ),
        windowDrafts: <int, WindowSetpointDraft>{
          101: WindowSetpointDraft.initial(moduleId: 101, zoneId: 1, slaveId: 1)
              .copyWithValue(WindowSetpointRegister.posATarget, 250)
              .copyWithValue(WindowSetpointRegister.posBTarget, 500)
              .copyWithValue(WindowSetpointRegister.ctrlMode, 1)
              .copyWithValue(WindowSetpointRegister.tempSetpoint, 245),
        },
      );
      final controller = ScadaController(
        client: client,
        configStore: store,
        logger: _FakeLogger(),
        topologyStore: _FakeTopologyStore(
          snapshot: _snapshot(
            manifest: _manifest(generation: 77, includeSchedule: true),
          ),
        ),
      );

      await controller.init();
      await _waitUntil(
        () =>
            client.operations.where((call) => call.values != null).length >=
            windowSetpointCommandBlocks.length,
      );

      final payloads = client.operations
          .where((call) => call.values != null)
          .map((call) => call.values!)
          .toList(growable: false);
      expect(payloads, hasLength(windowSetpointCommandBlocks.length));
      expect(
        payloads.map((values) => values[2]),
        orderedEquals(const <int>[
          5002,
          5004,
          5005,
          5006,
          5007,
          5015,
          5016,
          5017,
          5018,
          5019,
        ]),
      );
      expect(payloads.first, const <int>[1, 101, 5002, 2, 250, 500]);
      expect(payloads[1][4], 1);
      expect(payloads[1][6], 245);
      expect(
        controller.windowSetpointStatusForModule(101).message,
        'Auto-resynced after module restart',
      );

      controller.dispose();
    });

    test('saved window setpoints are synced on first online status', () async {
      final client = _OnlineWindowSetpointClient(generation: 77);
      final store = _FakeConfigStore(
        config: ScadaConfig.defaults().copyWith(
          pollIntervals: const PollIntervalsConfig(
            telemetryMs: 10,
            diagMs: 60000,
            commandPollMs: 50,
            uploadPollMs: 100,
          ),
        ),
        windowDrafts: <int, WindowSetpointDraft>{
          101: WindowSetpointDraft.initial(moduleId: 101, zoneId: 1, slaveId: 1)
              .copyWithValue(WindowSetpointRegister.posATarget, 111)
              .copyWithValue(WindowSetpointRegister.posBTarget, 222),
        },
      );
      final controller = ScadaController(
        client: client,
        configStore: store,
        logger: _FakeLogger(),
        topologyStore: _FakeTopologyStore(
          snapshot: _snapshot(
            manifest: _manifest(generation: 77, includeSchedule: true),
          ),
        ),
      );

      await controller.init();
      await _waitUntil(
        () =>
            client.operations.where((call) => call.values != null).length >=
            windowSetpointCommandBlocks.length,
      );

      final payloads = client.operations
          .where((call) => call.values != null)
          .map((call) => call.values!)
          .toList(growable: false);
      expect(payloads.first, const <int>[1, 101, 5002, 2, 111, 222]);
      expect(
        controller.clientTrace.any((line) => line.contains('first_online')),
        isTrue,
      );

      controller.dispose();
    });

    test('saved window setpoints resync after transport outage', () async {
      final client = _TransportOutageWindowSetpointClient(generation: 77);
      final store = _FakeConfigStore(
        config: ScadaConfig.defaults().copyWith(
          pollIntervals: const PollIntervalsConfig(
            telemetryMs: 10,
            diagMs: 60000,
            commandPollMs: 50,
            uploadPollMs: 100,
          ),
        ),
        windowDrafts: <int, WindowSetpointDraft>{
          101: WindowSetpointDraft.initial(moduleId: 101, zoneId: 1, slaveId: 1)
              .copyWithValue(WindowSetpointRegister.posATarget, 333)
              .copyWithValue(WindowSetpointRegister.posBTarget, 444),
        },
      );
      final controller = ScadaController(
        client: client,
        configStore: store,
        logger: _FakeLogger(),
        topologyStore: _FakeTopologyStore(
          snapshot: _snapshot(
            manifest: _manifest(generation: 77, includeSchedule: true),
          ),
        ),
      );

      await controller.init();
      await _waitUntil(
        () =>
            client.operations.where((call) => call.values != null).length >=
            windowSetpointCommandBlocks.length,
      );

      client.failNextStatusRead = true;
      await _waitUntil(
        () => controller.clientTrace.any(
          (line) => line.contains('resync session reset reason=poll_error'),
        ),
      );
      expect(client.disconnectCount, 0);
      await _waitUntil(
        () =>
            client.operations.where((call) => call.values != null).length >=
            windowSetpointCommandBlocks.length * 2,
      );

      final payloads = client.operations
          .where((call) => call.values != null)
          .map((call) => call.values!)
          .toList(growable: false);
      expect(payloads[windowSetpointCommandBlocks.length], const <int>[
        1,
        101,
        5002,
        2,
        333,
        444,
      ]);

      controller.dispose();
    });

    test('legacy reaction draft at register 243 is ignored', () async {
      final draft = WindowSetpointDraft.fromJson(<String, dynamic>{
        'module_id': 101,
        'zone_id': 1,
        'slave_id': 1,
        'values': <String, int>{'243': 5000},
      });

      expect(draft?.valueFor(WindowSetpointRegister.airTempTarget), 250);
      expect(draft?.valueFor(WindowSetpointRegister.curtainCtrlMode), 0);
    });

    test('window writable register model excludes curtain status range', () {
      expect(windowSetpointRegisters, contains(243));
      expect(windowSetpointRegisters, contains(266));
      expect(windowSetpointRegisters, contains(274));
      expect(windowSetpointRegisters, contains(275));
      expect(windowSetpointRegisters, contains(276));
      for (var register = 267; register <= 273; register++) {
        expect(windowSetpointRegisters, isNot(contains(register)));
      }
    });

    test(
      'lighting feedback fields resolve semantic points from points window',
      () async {
        final controller = ScadaController(
          client: _LightingFeedbackModbusTcpClient(),
          configStore: _FakeConfigStore(),
          logger: _FakeLogger(),
          topologyStore: _FakeTopologyStore(
            snapshot: _snapshot(
              manifest: _manifestWithLightingFeedback(generation: 77),
            ),
          ),
        );

        await controller.init();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final fields = controller.lightingFeedbackFieldsForModule(101);
        expect(
          fields.map((item) => item.semanticName),
          orderedEquals(const <String>[
            'current_dli',
            'light_output',
            'light_status_bits',
          ]),
        );
        expect(fields[0].telemetry?.value, closeTo(18.75, 0.001));
        expect(fields[1].telemetry?.value.round(), 50);
        expect(fields[2].telemetry?.value.round(), 3);

        controller.dispose();
      },
    );
  });
}

WindowSetpointDraft _dirtyEveryWindowBlock(WindowSetpointDraft draft) {
  return draft
      .copyWithValue(WindowSetpointRegister.posATarget, 1)
      .copyWithValue(WindowSetpointRegister.ctrlMode, 1)
      .copyWithValue(WindowSetpointRegister.humStep, 1)
      .copyWithValue(WindowSetpointRegister.rainWindwardPercent, 1)
      .copyWithValue(WindowSetpointRegister.tempStepMaxIndex, 1)
      .copyWithValue(WindowSetpointRegister.curtainManualTarget, 1)
      .copyWithValue(WindowSetpointRegister.curtainRadiationThreshold, 1)
      .copyWithValue(WindowSetpointRegister.curtainHumLowThreshold, 1)
      .copyWithValue(WindowSetpointRegister.curtainFaultResetToken, 1)
      .copyWithValue(WindowSetpointRegister.airTempTarget, 1)
      .copyWithValue(WindowSetpointRegister.airHumTarget, 1);
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
  bool includeZone2 = false,
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
      if (includeZone2)
        <String, dynamic>{
          'module_id': 102,
          'module_type': 1,
          'bus_type': 1,
          'bus_index': 0,
          'slave_id': 2,
          'zone_id': 2,
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
              'cmd_id': 5001,
              'module_id': 101,
              'fc': 16,
              'start_reg': 110,
              'max_reg_count': 13,
              'payload_offset': 0,
              'timeout_ms': scheduleTimeoutMs,
              'ack_point_id': 0,
              'cmd_kind': 'generic',
            },
          ]
        : const <Map<String, dynamic>>[],
    'policies': const <Map<String, dynamic>>[],
  });
}

TopologyManifest _manifestUnknownLightingProfile({required int generation}) {
  return TopologyManifest.fromJson(<String, dynamic>{
    'schema_version': '2.0',
    'generation': generation,
    'topology_id': 1,
    'modules': <Map<String, dynamic>>[
      <String, dynamic>{
        'module_id': 150,
        'module_type': 1,
        'bus_type': 1,
        'bus_index': 0,
        'slave_id': 7,
        'zone_id': 7,
        'capability_mask': 0,
        'user_param0': 0,
        'user_param1': 0,
      },
    ],
    'requests': const <Map<String, dynamic>>[],
    'points': const <Map<String, dynamic>>[],
    'commands': const <Map<String, dynamic>>[],
    'policies': const <Map<String, dynamic>>[],
  });
}

TopologyManifest _manifestWithLightingFeedback({required int generation}) {
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
    ],
    'requests': const <Map<String, dynamic>>[],
    'points': const <Map<String, dynamic>>[
      <String, dynamic>{
        'point_id': 10134,
        'module_id': 101,
        'req_id': 1,
        'point_type': 5,
        'scale_pow10': 0,
        'publish_index': 18,
        'quality_policy': 1,
        'stale_timeout_s': 10,
        'alarm_low': 0,
        'alarm_high': 0,
        'semantic_name': 'current_dli',
      },
      <String, dynamic>{
        'point_id': 10135,
        'module_id': 101,
        'req_id': 1,
        'point_type': 5,
        'scale_pow10': 0,
        'publish_index': 19,
        'quality_policy': 1,
        'stale_timeout_s': 10,
        'alarm_low': 0,
        'alarm_high': 0,
        'semantic_name': 'light_output',
      },
      <String, dynamic>{
        'point_id': 10136,
        'module_id': 101,
        'req_id': 1,
        'point_type': 6,
        'scale_pow10': 0,
        'publish_index': 20,
        'quality_policy': 1,
        'stale_timeout_s': 10,
        'alarm_low': 0,
        'alarm_high': 0,
        'semantic_name': 'light_status_bits',
      },
    ],
    'commands': const <Map<String, dynamic>>[],
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
    Map<int, WindowSetpointDraft>? windowDrafts,
  }) : _lightingDrafts = Map<int, LightingScheduleDraft>.from(
         lightingDrafts ?? const <int, LightingScheduleDraft>{},
       ),
       _windowDrafts = Map<int, WindowSetpointDraft>.from(
         windowDrafts ?? const <int, WindowSetpointDraft>{},
       );

  final ScadaConfig? config;
  final Map<int, LightingScheduleDraft> _lightingDrafts;
  final Map<int, WindowSetpointDraft> _windowDrafts;

  Map<int, LightingScheduleDraft> get lightingDrafts =>
      Map<int, LightingScheduleDraft>.unmodifiable(_lightingDrafts);
  Map<int, WindowSetpointDraft> get windowDrafts =>
      Map<int, WindowSetpointDraft>.unmodifiable(_windowDrafts);

  @override
  Future<ScadaConfig> load() async => config ?? ScadaConfig.defaults();

  @override
  Future<void> save(ScadaConfig config) async {}

  @override
  Future<Map<int, LightingScheduleDraft>> loadLightingDrafts() async {
    return Map<int, LightingScheduleDraft>.from(_lightingDrafts);
  }

  @override
  Future<void> saveLightingDrafts(
    Map<int, LightingScheduleDraft> drafts,
  ) async {
    _lightingDrafts
      ..clear()
      ..addAll(drafts);
  }

  @override
  Future<Map<int, WindowSetpointDraft>> loadWindowSetpointDrafts() async {
    return Map<int, WindowSetpointDraft>.from(_windowDrafts);
  }

  @override
  Future<void> saveWindowSetpointDrafts(
    Map<int, WindowSetpointDraft> drafts,
  ) async {
    _windowDrafts
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

class _WindowDebugRegisterClient extends _FakeModbusTcpClient {
  _WindowDebugRegisterClient({required super.generation});

  int debugReads = 0;

  @override
  Future<List<int>> readHoldingRegisters({
    required int unitId,
    required int startAddress,
    required int count,
  }) async {
    if (unitId == 1 && startAddress == 217) {
      debugReads += 1;
      return const <int>[0x1234];
    }
    return super.readHoldingRegisters(
      unitId: unitId,
      startAddress: startAddress,
      count: count,
    );
  }
}

class _WindowSetpointWriteClient extends _FakeModbusTcpClient {
  _WindowSetpointWriteClient({required super.generation});

  final List<_WriteCall> operations = <_WriteCall>[];
  int _lastAppliedTrigger = 0;
  int _lastResult = 2;
  int _lastIoErr = 0;
  int _nextResult = 2;
  int _nextIoErr = 0;

  @override
  Future<List<int>> readHoldingRegisters({
    required int unitId,
    required int startAddress,
    required int count,
  }) async {
    if (startAddress == 1240) {
      final regs = List<int>.filled(24, 0);
      regs[21] = _lastAppliedTrigger;
      regs[22] = _lastAppliedTrigger == 0 ? 0 : _lastResult;
      regs[23] = _lastIoErr;
      return regs.sublist(0, count);
    }
    if (startAddress == 1261) {
      return <int>[
        _lastAppliedTrigger,
        _lastResult,
        _lastIoErr,
      ].sublist(0, count);
    }
    return super.readHoldingRegisters(
      unitId: unitId,
      startAddress: startAddress,
      count: count,
    );
  }

  @override
  Future<void> writeMultipleRegisters({
    required int unitId,
    required int startAddress,
    required List<int> values,
  }) async {
    operations.add(
      _WriteCall(
        unitId: unitId,
        startAddress: startAddress,
        values: List<int>.from(values),
      ),
    );
  }

  @override
  Future<void> writeSingleRegister({
    required int unitId,
    required int address,
    required int value,
  }) async {
    if (address == 1260) {
      _lastAppliedTrigger = value;
      _lastResult = _nextResult;
      _lastIoErr = _nextIoErr;
      _nextResult = 2;
      _nextIoErr = 0;
    }
    operations.add(
      _WriteCall(unitId: unitId, startAddress: address, singleValue: value),
    );
  }
}

class _IoErrWindowSetpointWriteClient extends _WindowSetpointWriteClient {
  _IoErrWindowSetpointWriteClient({required super.generation});

  @override
  Future<void> writeMultipleRegisters({
    required int unitId,
    required int startAddress,
    required List<int> values,
  }) async {
    await super.writeMultipleRegisters(
      unitId: unitId,
      startAddress: startAddress,
      values: values,
    );
    _nextResult = 2;
    _nextIoErr = 1;
  }
}

class _RecoveringWindowSetpointClient extends _WindowSetpointWriteClient {
  _RecoveringWindowSetpointClient({required super.generation});

  int _statusReadCount = 0;

  @override
  Future<List<int>> readHoldingRegisters({
    required int unitId,
    required int startAddress,
    required int count,
  }) async {
    if (startAddress == 1080) {
      _statusReadCount += 1;
      final slave1Online = _statusReadCount >= 2;
      final regs = <int>[
        ..._slaveStatusBlock(
          statusFlags: slave1Online ? 0x0001 : 0x0002,
          dataVersion: slave1Online ? 1 : 9,
        ),
        ..._slaveStatusBlock(statusFlags: 0x0001, dataVersion: 1),
      ];
      return regs.sublist(0, count);
    }
    return super.readHoldingRegisters(
      unitId: unitId,
      startAddress: startAddress,
      count: count,
    );
  }
}

class _OnlineWindowSetpointClient extends _WindowSetpointWriteClient {
  _OnlineWindowSetpointClient({required super.generation});

  @override
  Future<List<int>> readHoldingRegisters({
    required int unitId,
    required int startAddress,
    required int count,
  }) async {
    if (startAddress == 1080) {
      final regs = <int>[
        ..._slaveStatusBlock(statusFlags: 0x0001, dataVersion: 1),
        ..._slaveStatusBlock(statusFlags: 0x0001, dataVersion: 1),
      ];
      return regs.sublist(0, count);
    }
    return super.readHoldingRegisters(
      unitId: unitId,
      startAddress: startAddress,
      count: count,
    );
  }
}

class _TransportOutageWindowSetpointClient extends _OnlineWindowSetpointClient {
  _TransportOutageWindowSetpointClient({required super.generation});

  bool failNextStatusRead = false;
  int disconnectCount = 0;

  @override
  Future<void> disconnect() async {
    disconnectCount += 1;
  }

  @override
  Future<List<int>> readHoldingRegisters({
    required int unitId,
    required int startAddress,
    required int count,
  }) async {
    if (startAddress == 1080 && failNextStatusRead) {
      failNextStatusRead = false;
      throw ModbusTcpException('response timeout (1 consecutive)');
    }
    return super.readHoldingRegisters(
      unitId: unitId,
      startAddress: startAddress,
      count: count,
    );
  }
}

List<int> _slaveStatusBlock({
  required int statusFlags,
  required int dataVersion,
}) {
  return <int>[statusFlags, 0, 0, 0, 0, dataVersion, 0, 0];
}

class _WriteCall {
  const _WriteCall({
    required this.unitId,
    required this.startAddress,
    this.values,
    this.singleValue,
  });

  final int unitId;
  final int startAddress;
  final List<int>? values;
  final int? singleValue;
}

class _DelayedWindowSetpointWriteClient extends _WindowSetpointWriteClient {
  _DelayedWindowSetpointWriteClient({required super.generation});

  int pollReads = 0;
  int? _pendingTrigger;
  int _pendingPolls = 0;

  @override
  Future<List<int>> readHoldingRegisters({
    required int unitId,
    required int startAddress,
    required int count,
  }) async {
    if (startAddress == 1261) {
      pollReads += 1;
      if (_pendingTrigger != null) {
        _pendingPolls += 1;
        if (_pendingPolls < 2) {
          return <int>[0, 1, 0].sublist(0, count);
        }
        final applied = _pendingTrigger!;
        _pendingTrigger = null;
        return <int>[applied, 2, 0].sublist(0, count);
      }
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
      _pendingTrigger = value;
      _pendingPolls = 0;
    }
    await super.writeSingleRegister(
      unitId: unitId,
      address: address,
      value: value,
    );
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

class _LightingFeedbackModbusTcpClient extends ModbusTcpClient {
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
      regs[4] = 21;
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
      return <int>[0, 0, 0, 0x0001, 2, 0, 0, 77, 0, 540].sublist(0, count);
    }
    if (startAddress >= 0 && startAddress < 126) {
      final rows = List<List<int>>.generate(
        21,
        (index) => _pointRow(
          value: index == 18
              ? 18.75
              : (index == 19 ? 50.0 : (index == 20 ? 3.0 : 0.0)),
          quality: 0,
          ageSec: index >= 18 ? 5 : 0,
          moduleId: 101,
          flags: index >= 18 ? 1 : 0,
        ),
      );
      final regs = rows.expand((row) => row).toList(growable: false);
      return regs.sublist(startAddress, startAddress + count);
    }
    if (startAddress == 1080) {
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
  List<int> commandStateForTrigger(int trigger) => <int>[trigger, 13, 0];
}

abstract class _ScheduleApplyClientBase extends _FakeModbusTcpClient {
  _ScheduleApplyClientBase() : super(generation: 77);

  int currentTrigger = 0;
  DateTime? triggerWrittenAt;
  int? lastPayloadStartAddress;
  List<int>? lastPayloadWrite;
  int? lastTriggerAddress;
  final List<String> writeOrder = <String>[];

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
      lastTriggerAddress = address;
      currentTrigger = value & 0xFFFF;
      triggerWrittenAt = DateTime.now();
      writeOrder.add('trigger');
    }
  }

  @override
  Future<void> writeMultipleRegisters({
    required int unitId,
    required int startAddress,
    required List<int> values,
  }) async {
    lastPayloadStartAddress = startAddress;
    lastPayloadWrite = List<int>.from(values);
    writeOrder.add('payload');
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

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition was not met within ${timeout.inMilliseconds}ms');
}
