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
  bool _running = false;
  int _txSeq = 1;
  int _reconnectAttempt = 0;

  Future<void> start() async {
    if (_running) {
      return;
    }
    _running = true;
    unawaited(_connectLoop());
  }

  Future<void> stop() async {
    _running = false;
    _heartbeatTimer?.cancel();
    await _readSub?.cancel();
    await _socket?.close();
    _connectedController.add(false);
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

        _connectedController.add(true);
        _reconnectAttempt = 0;
        _startHeartbeat();

        _readSub = socket.listen(
          (chunk) {
            final frames = _parser.addBytes(Uint8List.fromList(chunk));
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
        _connectedController.add(false);
      }

      if (!_running) {
        return;
      }
      _reconnectAttempt++;
      final delay = min(10, 1 << min(_reconnectAttempt, 4));
      await Future<void>.delayed(Duration(seconds: delay));
    }
  }

  void _onDisconnected() {
    _heartbeatTimer?.cancel();
    _socket = null;
    _readSub = null;
    _connectedController.add(false);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      sendFrame(MsgType.heartbeat, Uint8List(0));
    });
  }

  Future<void> sendFrame(int msgType, Uint8List payload) async {
    final sock = _socket;
    if (sock == null) {
      return;
    }
    try {
      final frame = _codec.encode(msgType: msgType, seq: _txSeq++, payload: payload);
      sock.add(frame);
      await sock.flush();
    } catch (_) {
      _onDisconnected();
    }
  }

  Future<void> dispose() async {
    await stop();
    await _framesController.close();
    await _connectedController.close();
  }
}
