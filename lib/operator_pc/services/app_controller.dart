import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/operator_models.dart';
import 'master_tcp_client.dart';
import 'protocol.dart';
import 'storage_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.host,
    required this.port,
  }) {
    _client = MasterTcpClient(host: host, port: port);
  }

  final String host;
  final int port;

  late final MasterTcpClient _client;
  final StorageService storage = StorageService();

  MasterStatus status = MasterStatus.initial();
  List<SensorPoint> sensors = List<SensorPoint>.generate(
    kSensorCount,
    (i) => SensorPoint(
      id: i,
      value: 0,
      quality: SensorQuality.offline,
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
    ),
  );
  final List<EventItem> events = <EventItem>[];

  int _lastEventSeen = 0;
  String setpointStatus = 'idle';
  bool setpointBusy = false;
  String? lastExportPath;
  List<double> currentConfig = List<double>.filled(32, 0);

  StreamSubscription<bool>? _connSub;
  StreamSubscription<ProtocolFrame>? _frameSub;

  Future<void> init() async {
    await storage.init();

    _connSub = _client.connection.listen((connected) {
      status = status.copyWith(connected: connected);
      notifyListeners();
      if (connected) {
        unawaited(_runResync());
      }
    });

    _frameSub = _client.frames.listen(_onFrame);
    await _client.start();
  }

  Future<void> _runResync() async {
    final hello = Uint8List(4);
    final bd = ByteData.sublistView(hello);
    bd.setUint32(0, _lastEventSeen, Endian.little);

    await _client.sendFrame(MsgType.hello, hello);
    await _client.sendFrame(MsgType.statusReq, Uint8List(0));
    await _client.sendFrame(MsgType.getConfigReq, Uint8List(0));
  }

  Future<void> _onFrame(ProtocolFrame frame) async {
    switch (frame.msgType) {
      case MsgType.heartbeat:
        break;
      case MsgType.helloAck:
        _parseHelloAck(frame.payload);
        break;
      case MsgType.statusResp:
        _parseStatus(frame.payload);
        break;
      case MsgType.getConfigResp:
        _parseConfig(frame.payload);
        break;
      case MsgType.snapshot:
        await _parseSnapshot(frame.payload);
        break;
      case MsgType.event:
        await _parseEvent(frame.payload);
        break;
      case MsgType.setpointsValidateAck:
        _parseSetpointValidate(frame.payload);
        break;
      case MsgType.setpointsApplyAck:
        _parseSetpointApply(frame.payload);
        break;
      default:
        break;
    }
  }

  void _parseHelloAck(Uint8List payload) {
    if (payload.length < 28) {
      return;
    }
    final d = ByteData.sublistView(payload);
    final activeConfigVersion = d.getUint32(20, Endian.little);
    _lastEventSeen = d.getUint32(24, Endian.little);
    status = status.copyWith(activeConfigVersion: activeConfigVersion);
    notifyListeners();
  }

  void _parseStatus(Uint8List payload) {
    if (payload.length < 88) {
      return;
    }
    final lastErr = ByteData.sublistView(payload).getUint32(84, Endian.little);
    status = status.copyWith(lastErrorCode: lastErr);
    notifyListeners();
  }

  void _parseConfig(Uint8List payload) {
    if (payload.length < 128) {
      return;
    }
    final d = ByteData.sublistView(payload);
    currentConfig = List<double>.generate(
      32,
      (i) => d.getFloat32(i * 4, Endian.little),
    );
    notifyListeners();
  }

  Future<void> _parseSnapshot(Uint8List payload) async {
    final snap = SnapshotData.tryParse(payload);
    if (snap == null) {
      return;
    }

    final ts = DateTime.now();
    sensors = List<SensorPoint>.generate(kSensorCount, (i) {
      return SensorPoint(
        id: i,
        value: snap.values[i],
        quality: snap.quality[i],
        timestamp: ts,
      );
    });

    status = status.copyWith(lastSnapshotAt: ts);
    notifyListeners();

    unawaited(storage.logSnapshot(sensors));
  }

  Future<void> _parseEvent(Uint8List payload) async {
    if (payload.length < 17) {
      return;
    }
    final d = ByteData.sublistView(payload);
    final eventId = d.getUint32(0, Endian.little);

    if (eventId <= _lastEventSeen || events.any((e) => e.eventId == eventId)) {
      await _ackEvent(eventId);
      return;
    }

    final severity = severityFromByte(d.getUint8(4));
    final code = d.getUint16(5, Endian.little);
    final source = d.getUint16(7, Endian.little);
    final value = d.getFloat32(9, Endian.little);
    final timestampMs = d.getUint32(13, Endian.little);

    final event = EventItem(
      eventId: eventId,
      severity: severity,
      code: code,
      source: source,
      value: value,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      acked: true,
    );

    _lastEventSeen = eventId;
    events.insert(0, event);
    if (events.length > 2048) {
      events.removeLast();
    }

    notifyListeners();

    unawaited(storage.logEvent(event));
    await _ackEvent(eventId);
  }

  Future<void> _ackEvent(int eventId) async {
    final payload = Uint8List(4);
    ByteData.sublistView(payload).setUint32(0, eventId, Endian.little);
    await _client.sendFrame(MsgType.eventAck, payload);
  }

  Future<void> sendSetpoints({
    required int newVersion,
    required List<double> values,
    required String user,
  }) async {
    if (setpointBusy) {
      return;
    }

    setpointBusy = true;
    setpointStatus = 'in_progress';
    notifyListeners();

    try {
      final configPayload = Uint8List(128);
      final cfg = ByteData.sublistView(configPayload);
      for (var i = 0; i < 32; i++) {
        cfg.setFloat32(
          i * 4,
          i < values.length ? values[i] : 0,
          Endian.little,
        );
      }
      final payloadCrc = crc32(configPayload);

      final putPayload = Uint8List(136);
      final d = ByteData.sublistView(putPayload);
      d.setUint32(0, newVersion, Endian.little);
      d.setUint32(4, payloadCrc, Endian.little);
      putPayload.setRange(8, 136, configPayload);

      await _client.sendFrame(MsgType.setpointsPut, putPayload);
      await _client.sendFrame(MsgType.setpointsApplyReq, Uint8List(0));

      await storage.logSetpointChange(
        oldVersion: status.activeConfigVersion,
        newVersion: newVersion,
        user: user,
        summary: 'setpoints_v1_32f',
      );

      setpointStatus = 'submitted';
    } catch (e) {
      setpointStatus = 'failed: $e';
    } finally {
      setpointBusy = false;
      notifyListeners();
    }
  }

  void _parseSetpointValidate(Uint8List payload) {
    if (payload.isEmpty) {
      setpointStatus = 'validate_unknown';
      notifyListeners();
      return;
    }
    switch (payload[0]) {
      case 0:
        setpointStatus = 'validate_ok';
        break;
      case 1:
        setpointStatus = 'validate_len';
        break;
      case 2:
        setpointStatus = 'validate_crc';
        break;
      case 3:
        setpointStatus = 'validate_range';
        break;
      case 4:
        setpointStatus = 'validate_busy';
        break;
      default:
        setpointStatus = 'validate_unknown';
        break;
    }
    notifyListeners();
  }

  void _parseSetpointApply(Uint8List payload) {
    if (payload.length < 5) {
      setpointStatus = 'apply_unknown';
      notifyListeners();
      return;
    }
    final d = ByteData.sublistView(payload);
    final applied = d.getUint8(0) == 0;
    final version = d.getUint32(1, Endian.little);

    status = status.copyWith(activeConfigVersion: version);
    setpointStatus = applied ? 'applied' : 'apply_failed';
    notifyListeners();
  }

  Future<void> exportCsv(DateTime from, DateTime to) async {
    lastExportPath = await storage.exportCsv(from: from, to: to);
    notifyListeners();
  }

  Future<void> exportXlsx(DateTime from, DateTime to) async {
    lastExportPath = await storage.exportXlsx(from: from, to: to);
    notifyListeners();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _frameSub?.cancel();
    unawaited(_client.dispose());
    unawaited(storage.dispose());
    super.dispose();
  }
}
