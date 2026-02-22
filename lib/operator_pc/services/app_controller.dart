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
  final Map<int, int> rxByType = <int, int>{};

  int _lastEventSeen = 0;
  String setpointStatus = 'idle';
  bool setpointBusy = false;
  String? lastExportPath;
  int lastRxMsgType = 0;
  int lastRxPayloadLen = 0;
  DateTime? lastRxAt;
  int rawRxBytes = 0;
  int rawRxChunks = 0;
  int parsedFrames = 0;
  int rawTxBytes = 0;
  int rawTxFrames = 0;
  List<double> currentConfig = List<double>.filled(32, 0);
  int channelsPerBlock = kChannelsPerBlock;
  List<BlockLayoutItem> blockLayoutItems = const <BlockLayoutItem>[];

  StreamSubscription<bool>? _connSub;
  StreamSubscription<ProtocolFrame>? _frameSub;
  Timer? _statusPollTimer;
  Completer<int>? _setpointValidateAck;
  Completer<({bool applied, int version})>? _setpointApplyAck;

  static const Duration _setpointValidateTimeout = Duration(seconds: 5);
  static const Duration _setpointApplyTimeout = Duration(seconds: 5);

  Future<void> init() async {
    await storage.init();

    _connSub = _client.connection.listen((connected) {
      status = status.copyWith(connected: connected);
      if (!connected) {
        _failPendingSetpointAcks();
      }
      notifyListeners();
      if (connected) {
        unawaited(_runResync());
        _startStatusPoll();
      } else {
        _stopStatusPoll();
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
    await _client.sendFrame(MsgType.getBlockLayoutReq, Uint8List(0));
  }

  void _startStatusPoll() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      rawRxBytes = _client.rxBytes;
      rawRxChunks = _client.rxChunks;
      parsedFrames = _client.parsedFrames;
      rawTxBytes = _client.txBytes;
      rawTxFrames = _client.txFrames;
      if (!status.connected) {
        notifyListeners();
        return;
      }
      unawaited(_client.sendFrame(MsgType.statusReq, Uint8List(0)));
      notifyListeners();
    });
  }

  void _stopStatusPoll() {
    _statusPollTimer?.cancel();
    _statusPollTimer = null;
  }

  Future<void> _onFrame(ProtocolFrame frame) async {
    lastRxAt = DateTime.now();
    lastRxMsgType = frame.msgType;
    lastRxPayloadLen = frame.payload.length;
    rxByType.update(frame.msgType, (v) => v + 1, ifAbsent: () => 1);
    notifyListeners();

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
      case MsgType.blockLayoutResp:
        _parseBlockLayout(frame.payload);
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
    if (payload.isEmpty) {
      return;
    }
    final d = ByteData.sublistView(payload);
    final tcpConnectCount = payload.length >= 12
        ? d.getUint32(8, Endian.little)
        : status.tcpConnectCount;
    final tcpDisconnectCount = payload.length >= 16
        ? d.getUint32(12, Endian.little)
        : status.tcpDisconnectCount;
    final lastErr = payload.length >= 88
        ? d.getUint32(84, Endian.little)
        : status.lastErrorCode;

    var controlMode = status.controlMode;
    var autonomousReason = status.autonomousReason;
    var lastMasterSeenMs = status.lastMasterSeenMs;
    if (payload.length >= 94) {
      controlMode = d.getUint8(88);
      autonomousReason = d.getUint8(89);
      lastMasterSeenMs = d.getUint32(90, Endian.little);
    }

    status = status.copyWith(
      tcpConnectCount: tcpConnectCount,
      tcpDisconnectCount: tcpDisconnectCount,
      lastErrorCode: lastErr,
      controlMode: controlMode,
      autonomousReason: autonomousReason,
      lastMasterSeenMs: lastMasterSeenMs,
    );
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

  void _parseBlockLayout(Uint8List payload) {
    if (payload.length < 4) {
      return;
    }
    final d = ByteData.sublistView(payload);
    final cpb = d.getUint8(0);
    final itemCount = d.getUint8(1);
    d.getUint16(2, Endian.little); // reserved:uint16
    final maxByPayload = (payload.length - 4) ~/ 8;
    final safeCount = itemCount < maxByPayload ? itemCount : maxByPayload;

    final items = <BlockLayoutItem>[];
    var offset = 4;
    for (var i = 0; i < safeCount; i++) {
      final blockNo = d.getUint8(offset);
      final slaveId = d.getUint8(offset + 1);
      final startReg = d.getUint16(offset + 2, Endian.little);
      final sensorCount = d.getUint16(offset + 4, Endian.little);
      final sensorBase = d.getUint16(offset + 6, Endian.little);
      offset += 8;

      items.add(
        BlockLayoutItem(
          blockNo: blockNo,
          slaveId: slaveId,
          startReg: startReg,
          sensorCount: sensorCount,
          sensorBase: sensorBase,
        ),
      );
    }

    channelsPerBlock = cpb > 0 ? cpb : kChannelsPerBlock;
    blockLayoutItems = items;
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

    status = status.copyWith(lastSnapshotAt: ts, lastSnapshotId: snap.snapshotId);
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
    if (!status.connected) {
      setpointStatus = 'failed: disconnected';
      notifyListeners();
      return;
    }

    setpointBusy = true;
    setpointStatus = 'in_progress';
    notifyListeners();

    try {
      final oldVersion = status.activeConfigVersion;
      _setpointValidateAck = Completer<int>();
      _setpointApplyAck = Completer<({bool applied, int version})>();

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
      final validateCode = await _setpointValidateAck!.future.timeout(
        _setpointValidateTimeout,
      );
      if (validateCode != 0) {
        return;
      }

      await _client.sendFrame(MsgType.setpointsApplyReq, Uint8List(0));
      final apply = await _setpointApplyAck!.future.timeout(_setpointApplyTimeout);
      if (!apply.applied) {
        setpointStatus = 'apply_failed';
        return;
      }

      status = status.copyWith(activeConfigVersion: apply.version);

      await storage.logSetpointChange(
        oldVersion: oldVersion,
        newVersion: newVersion,
        user: user,
        summary: 'setpoints_v1_32f',
      );

      setpointStatus = 'applied';
    } catch (e) {
      setpointStatus = 'failed: $e';
    } finally {
      _setpointValidateAck = null;
      _setpointApplyAck = null;
      setpointBusy = false;
      notifyListeners();
    }
  }

  void _parseSetpointValidate(Uint8List payload) {
    final code = payload.isEmpty ? 255 : payload[0];
    switch (code) {
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
    if (_setpointValidateAck != null && !_setpointValidateAck!.isCompleted) {
      _setpointValidateAck!.complete(code);
    }
    notifyListeners();
  }

  void _parseSetpointApply(Uint8List payload) {
    if (payload.length < 5) {
      setpointStatus = 'apply_unknown';
      if (_setpointApplyAck != null && !_setpointApplyAck!.isCompleted) {
        _setpointApplyAck!.complete((applied: false, version: 0));
      }
      notifyListeners();
      return;
    }
    final d = ByteData.sublistView(payload);
    final applied = d.getUint8(0) == 0;
    final version = d.getUint32(1, Endian.little);

    status = status.copyWith(activeConfigVersion: version);
    setpointStatus = applied ? 'applied' : 'apply_failed';
    if (_setpointApplyAck != null && !_setpointApplyAck!.isCompleted) {
      _setpointApplyAck!.complete((applied: applied, version: version));
    }
    notifyListeners();
  }

  void _failPendingSetpointAcks() {
    if (_setpointValidateAck != null && !_setpointValidateAck!.isCompleted) {
      _setpointValidateAck!.completeError(StateError('Disconnected'));
    }
    if (_setpointApplyAck != null && !_setpointApplyAck!.isCompleted) {
      _setpointApplyAck!.completeError(StateError('Disconnected'));
    }
  }

  Future<void> exportCsv(DateTime from, DateTime to) async {
    lastExportPath = await storage.exportCsv(
      from: from,
      to: to,
      resolveSensor: resolveSensorByLayout,
      channelNameByIndex: channelNameByIndex,
      decodeSource: decodeSourceByLayout,
    );
    notifyListeners();
  }

  Future<void> exportXlsx(DateTime from, DateTime to) async {
    lastExportPath = await storage.exportXlsx(
      from: from,
      to: to,
      resolveSensor: resolveSensorByLayout,
      channelNameByIndex: channelNameByIndex,
      decodeSource: decodeSourceByLayout,
    );
    notifyListeners();
  }

  List<int> get availableBlocks =>
      blockLayoutItems.map((e) => e.blockNo).toSet().toList()..sort();

  String channelNameByIndex(int channelIndex) {
    if (channelIndex < 0 || channelIndex >= kChannelNames.length) {
      return 'CH$channelIndex';
    }
    return kChannelNames[channelIndex];
  }

  ({int blockNo, int channelIndex})? resolveSensorByLayout(int sensorId) {
    if (blockLayoutItems.isEmpty) {
      if (sensorId < 0) {
        return null;
      }
      final cpb = channelsPerBlock > 0 ? channelsPerBlock : kChannelsPerBlock;
      return (blockNo: (sensorId ~/ cpb) + 1, channelIndex: sensorId % cpb);
    }
    for (final item in blockLayoutItems) {
      final start = item.sensorBase;
      final end = item.sensorBase + item.sensorCount;
      if (sensorId >= start && sensorId < end) {
        return (blockNo: item.blockNo, channelIndex: sensorId - item.sensorBase);
      }
    }
    return null;
  }

  String decodeSourceByLayout(int source) {
    final mapped = resolveSensorByLayout(source);
    if (mapped == null) {
      return 'Unknown source';
    }
    return 'Block ${mapped.blockNo} / ${channelNameByIndex(mapped.channelIndex)}';
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _frameSub?.cancel();
    _stopStatusPoll();
    unawaited(_client.dispose());
    unawaited(storage.dispose());
    super.dispose();
  }
}
