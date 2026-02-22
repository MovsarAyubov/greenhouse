import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class ModbusTcpException implements Exception {
  ModbusTcpException(this.message);

  final String message;

  @override
  String toString() => 'ModbusTcpException: $message';
}

class ModbusTcpClient {
  ModbusTcpClient({
    this.connectTimeout = const Duration(seconds: 4),
    this.responseTimeout = const Duration(milliseconds: 1800),
    this.maxConsecutiveTimeoutsBeforeDisconnect = 3,
  });

  final Duration connectTimeout;
  final Duration responseTimeout;
  final int maxConsecutiveTimeoutsBeforeDisconnect;

  Socket? _socket;
  StreamSubscription<List<int>>? _readSub;
  int _transactionId = 1;
  final Map<int, Completer<Uint8List>> _pending = <int, Completer<Uint8List>>{};
  final List<int> _rxBuffer = <int>[];
  Future<void> _requestChain = Future<void>.value();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  bool _connected = false;
  int _consecutiveTimeouts = 0;

  Stream<bool> get connection => _connectionController.stream;
  bool get isConnected => _connected;

  Future<void> connect(String host, int port) async {
    if (_socket != null) {
      return;
    }
    final socket = await Socket.connect(
      host,
      port,
      timeout: connectTimeout,
    );
    socket.setOption(SocketOption.tcpNoDelay, true);
    _socket = socket;
    _readSub = socket.listen(
      _onChunk,
      onDone: _onDisconnected,
      onError: (_) => _onDisconnected(),
      cancelOnError: true,
    );
    _setConnected(true);
    _consecutiveTimeouts = 0;
  }

  Future<void> disconnect() async {
    final sub = _readSub;
    _readSub = null;
    if (sub != null) {
      await sub.cancel();
    }

    final socket = _socket;
    _socket = null;
    if (socket != null) {
      await socket.close();
      socket.destroy();
    }

    _failAllPending(ModbusTcpException('disconnected'));
    _setConnected(false);
  }

  Future<List<int>> readHoldingRegisters({
    required int unitId,
    required int startAddress,
    required int count,
  }) async {
    if (count < 1 || count > 125) {
      throw ModbusTcpException('read count must be between 1 and 125');
    }
    final pdu = Uint8List(5);
    final bd = ByteData.sublistView(pdu);
    pdu[0] = 0x03;
    bd.setUint16(1, startAddress, Endian.big);
    bd.setUint16(3, count, Endian.big);
    final resp = await _request(unitId: unitId, pdu: pdu);
    if (resp.length < 2 || resp[0] != 0x03) {
      throw ModbusTcpException('invalid read response');
    }
    final byteCount = resp[1];
    if (byteCount != count * 2 || resp.length < 2 + byteCount) {
      throw ModbusTcpException('invalid read byte count');
    }
    final out = <int>[];
    for (var i = 0; i < count; i++) {
      out.add((resp[2 + i * 2] << 8) | resp[3 + i * 2]);
    }
    return out;
  }

  Future<void> writeSingleRegister({
    required int unitId,
    required int address,
    required int value,
  }) async {
    final pdu = Uint8List(5);
    final bd = ByteData.sublistView(pdu);
    pdu[0] = 0x06;
    bd.setUint16(1, address, Endian.big);
    bd.setUint16(3, value & 0xFFFF, Endian.big);
    final resp = await _request(unitId: unitId, pdu: pdu);
    if (resp.length < 5 || resp[0] != 0x06) {
      throw ModbusTcpException('invalid write single response');
    }
  }

  Future<void> writeMultipleRegisters({
    required int unitId,
    required int startAddress,
    required List<int> values,
  }) async {
    if (values.isEmpty || values.length > 123) {
      throw ModbusTcpException('write count must be between 1 and 123');
    }
    final pdu = Uint8List(6 + values.length * 2);
    final bd = ByteData.sublistView(pdu);
    pdu[0] = 0x10;
    bd.setUint16(1, startAddress, Endian.big);
    bd.setUint16(3, values.length, Endian.big);
    pdu[5] = values.length * 2;
    for (var i = 0; i < values.length; i++) {
      bd.setUint16(6 + i * 2, values[i] & 0xFFFF, Endian.big);
    }
    final resp = await _request(unitId: unitId, pdu: pdu);
    if (resp.length < 5 || resp[0] != 0x10) {
      throw ModbusTcpException('invalid write multiple response');
    }
  }

  Future<Uint8List> _request({
    required int unitId,
    required Uint8List pdu,
  }) {
    final completer = Completer<Uint8List>();
    int? requestTxId;
    _requestChain = _requestChain
        .catchError((_) {})
        .then((_) async {
          final socket = _socket;
          if (socket == null) {
            completer.completeError(ModbusTcpException('not connected'));
            return;
          }

          final txId = _nextTransactionId();
          requestTxId = txId;
          _pending[txId] = completer;
          final adu = _buildAdu(txId: txId, unitId: unitId, pdu: pdu);

          try {
            socket.add(adu);
            await socket.flush();
          } catch (e) {
            _pending.remove(txId);
            if (!completer.isCompleted) {
              completer.completeError(e);
            }
            await disconnect();
          }
        });

    return completer.future.timeout(
      responseTimeout,
      onTimeout: () {
        final txId = requestTxId;
        if (txId != null) {
          _pending.remove(txId);
        }
        _consecutiveTimeouts += 1;
        if (_consecutiveTimeouts >= maxConsecutiveTimeoutsBeforeDisconnect) {
          unawaited(disconnect());
        }
        final e = ModbusTcpException(
          'response timeout (${_consecutiveTimeouts} consecutive)',
        );
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
        throw e;
      },
    );
  }

  Uint8List _buildAdu({
    required int txId,
    required int unitId,
    required Uint8List pdu,
  }) {
    final data = Uint8List(7 + pdu.length);
    final bd = ByteData.sublistView(data);
    bd.setUint16(0, txId, Endian.big);
    bd.setUint16(2, 0, Endian.big);
    bd.setUint16(4, pdu.length + 1, Endian.big);
    data[6] = unitId & 0xFF;
    data.setRange(7, data.length, pdu);
    return data;
  }

  void _onChunk(List<int> chunk) {
    _rxBuffer.addAll(chunk);

    while (_rxBuffer.length >= 7) {
      final head = Uint8List.fromList(_rxBuffer.sublist(0, 7));
      final h = ByteData.sublistView(head);
      final txId = h.getUint16(0, Endian.big);
      final protoId = h.getUint16(2, Endian.big);
      final len = h.getUint16(4, Endian.big);

      if (protoId != 0 || len < 2) {
        _onDisconnected();
        return;
      }

      final fullLen = 6 + len;
      if (_rxBuffer.length < fullLen) {
        return;
      }

      final adu = Uint8List.fromList(_rxBuffer.sublist(0, fullLen));
      _rxBuffer.removeRange(0, fullLen);

      final pdu = Uint8List.fromList(adu.sublist(7));
      final pending = _pending.remove(txId);
      if (pending == null || pending.isCompleted) {
        continue;
      }
      _consecutiveTimeouts = 0;

      if (pdu.isNotEmpty && (pdu[0] & 0x80) == 0x80) {
        final code = pdu.length > 1 ? pdu[1] : 0;
        pending.completeError(
          ModbusTcpException('modbus exception code: $code'),
        );
      } else {
        pending.complete(pdu);
      }
    }
  }

  void _onDisconnected() {
    unawaited(disconnect());
  }

  int _nextTransactionId() {
    final value = _transactionId & 0xFFFF;
    _transactionId = (_transactionId + 1) & 0xFFFF;
    return value;
  }

  void _failAllPending(Object error) {
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(error);
      }
    }
    _pending.clear();
  }

  void _setConnected(bool value) {
    if (_connected == value) {
      return;
    }
    _connected = value;
    _connectionController.add(value);
  }

  Future<void> dispose() async {
    await disconnect();
    await _connectionController.close();
  }
}
