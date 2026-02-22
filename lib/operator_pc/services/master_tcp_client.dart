import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'protocol.dart';

class MasterTcpClient {
  MasterTcpClient({
    required this.host,
    required this.port,
  });

  final String host;
  final int port;

  final FrameCodec _codec = FrameCodec();
  final FrameParser _parser = FrameParser();

  final StreamController<ProtocolFrame> _framesController =
      StreamController<ProtocolFrame>.broadcast();
  final StreamController<bool> _connectedController =
      StreamController<bool>.broadcast();

  Stream<ProtocolFrame> get frames => _framesController.stream;
  Stream<bool> get connection => _connectedController.stream;

  Socket? _socket;
  StreamSubscription<List<int>>? _readSub;
  Timer? _heartbeatTimer;
  Timer? _livenessTimer;
  bool _running = false;
  bool _connected = false;
  int _txSeq = 1;
  int _reconnectAttempt = 0;
  DateTime _lastRxAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _rxBytes = 0;
  int _rxChunks = 0;
  int _parsedFrames = 0;
  int _txBytes = 0;
  int _txFrames = 0;
  int _noRxTimeoutHits = 0;
  Future<void> _sendChain = Future<void>.value();

  static const Duration _heartbeatPeriod = Duration(seconds: 1);
  static const Duration _rxTimeout = Duration(seconds: 12);
  static const int _maxNoRxTimeoutHits = 3;

  int get rxBytes => _rxBytes;
  int get rxChunks => _rxChunks;
  int get parsedFrames => _parsedFrames;
  int get txBytes => _txBytes;
  int get txFrames => _txFrames;

  Future<void> start() async {
    if (_running) {
      return;
    }
    _running = true;
    unawaited(_connectLoop());
  }

  Future<void> stop() async {
    _running = false;
    _stopTimers();
    await _tearDownConnection();
    _setConnected(false);
  }

  Future<void> _connectLoop() async {
    while (_running) {
      try {
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 3),
        );

        _socket = socket;
        _socket!.setOption(SocketOption.tcpNoDelay, true);
        _lastRxAt = DateTime.now();
        _rxBytes = 0;
        _rxChunks = 0;
        _parsedFrames = 0;
        _txBytes = 0;
        _txFrames = 0;
        _noRxTimeoutHits = 0;

        _setConnected(true);
        _reconnectAttempt = 0;
        _startHeartbeat();
        _startLivenessWatchdog();

        _readSub = socket.listen(
          (chunk) {
            _lastRxAt = DateTime.now();
            _noRxTimeoutHits = 0;
            _rxChunks += 1;
            _rxBytes += chunk.length;
            final frames = _parser.addBytes(Uint8List.fromList(chunk));
            _parsedFrames += frames.length;
            for (final frame in frames) {
              _framesController.add(frame);
            }
          },
          onDone: _onDisconnected,
          onError: (_) => _onDisconnected(),
          cancelOnError: true,
        );

        await _readSub?.asFuture<void>();
      } catch (_) {
        _setConnected(false);
      }

      if (!_running) {
        return;
      }
      _reconnectAttempt++;
      final baseDelay = min(10, 1 << min(_reconnectAttempt, 4));
      final jitterMs = Random().nextInt(750);
      final delayMs = baseDelay * 1000 + jitterMs;
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }

  void _setConnected(bool value) {
    if (_connected == value) {
      return;
    }
    _connected = value;
    _connectedController.add(value);
  }

  Future<void> _tearDownConnection() async {
    final sub = _readSub;
    _readSub = null;
    if (sub != null) {
      await sub.cancel();
    }

    final sock = _socket;
    _socket = null;
    if (sock != null) {
      await sock.close();
      sock.destroy();
    }
  }

  void _stopTimers() {
    _heartbeatTimer?.cancel();
    _livenessTimer?.cancel();
  }

  void _onDisconnected() {
    _stopTimers();
    unawaited(_tearDownConnection());
    _setConnected(false);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatPeriod, (_) {
      unawaited(sendFrame(MsgType.heartbeat, Uint8List(0)));
    });
  }

  void _startLivenessWatchdog() {
    _livenessTimer?.cancel();
    _livenessTimer = Timer.periodic(_heartbeatPeriod, (_) {
      final now = DateTime.now();
      if (now.difference(_lastRxAt) > _rxTimeout) {
        _noRxTimeoutHits += 1;
        if (_noRxTimeoutHits <= _maxNoRxTimeoutHits) {
          // Probe the peer before reconnecting: some servers are slow to emit
          // first frame after TCP accept.
          unawaited(sendFrame(MsgType.heartbeat, Uint8List(0)));
          unawaited(sendFrame(MsgType.statusReq, Uint8List(0)));
          return;
        }
        _onDisconnected();
      }
    });
  }

  Future<void> sendFrame(int msgType, Uint8List payload) async {
    _sendChain = _sendChain
        .catchError((_) {
          // Keep send chain alive after transient socket errors.
        })
        .then((_) async {
      final sock = _socket;
      if (sock == null) {
        return;
      }
      try {
        final frame = _codec.encode(
          msgType: msgType,
          seq: _txSeq++,
          payload: payload,
        );
        sock.add(frame);
        await sock.flush();
        _txFrames += 1;
        _txBytes += frame.length;
      } catch (_) {
        _onDisconnected();
      }
    });
    return _sendChain;
  }

  Future<void> dispose() async {
    await stop();
    await _framesController.close();
    await _connectedController.close();
  }
}
