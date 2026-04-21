import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

enum ModbusAddressMode { zeroBased, style4xxxx }

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
    this.addressMode = ModbusAddressMode.zeroBased,
  });

  Socket? _socket;
  StreamSubscription<List<int>>? _readSub;
  int _transactionId = 1;
  final List<int> _rxBuffer = <int>[];
  Future<void> _requestChain = Future<void>.value();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  bool _connected = false;
  int _consecutiveTimeouts = 0;
  Completer<Uint8List>? _activeRequest;
  int? _activeTransactionId;
  String? _lastHost;
  int? _lastPort;
  int _connectionId = 0;
  int _requestId = 0;

  final int maxConsecutiveTimeoutsBeforeDisconnect;
  Duration connectTimeout;
  Duration responseTimeout;
  ModbusAddressMode addressMode;
  void Function(String message)? traceSink;

  Stream<bool> get connection => _connectionController.stream;
  bool get isConnected => _connected;

  Future<void> connect(String host, int port) async {
    final previousHost = _lastHost;
    final previousPort = _lastPort;
    _lastHost = host;
    _lastPort = port;
    if (_socket != null) {
      if (previousHost == host && previousPort == port) {
        return;
      }
      await disconnect();
    }
    final socket = await Socket.connect(host, port, timeout: connectTimeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    _socket = socket;
    _connectionId += 1;
    _readSub = socket.listen(
      _onChunk,
      onDone: _onDisconnected,
      onError: (_) => _onDisconnected(),
      cancelOnError: true,
    );
    _setConnected(true);
    _consecutiveTimeouts = 0;
    _trace('connect conn=$_connectionId host=$host port=$port');
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

    _failActiveRequest(ModbusTcpException('disconnected'));
    _setConnected(false);
    _trace('disconnect conn=$_connectionId');
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
    bd.setUint16(1, _normalizeAddress(startAddress), Endian.big);
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
    bd.setUint16(1, _normalizeAddress(address), Endian.big);
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
    bd.setUint16(1, _normalizeAddress(startAddress), Endian.big);
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

  Future<Uint8List> _request({required int unitId, required Uint8List pdu}) {
    final requestId = ++_requestId;
    final fc = pdu.isEmpty ? 0 : pdu[0];
    final startAddress = pdu.length >= 3
        ? ((pdu[1] & 0xFF) << 8) | (pdu[2] & 0xFF)
        : -1;
    final qtyOrValueCount = pdu.length >= 5
        ? ((pdu[3] & 0xFF) << 8) | (pdu[4] & 0xFF)
        : -1;
    _trace(
      'request enqueue req=$requestId conn=$_connectionId '
      'fc=$fc start=$startAddress size=$qtyOrValueCount',
    );
    final operation = _requestChain.catchError((_) {}).then((_) async {
      final stopwatch = Stopwatch()..start();
      var finishLogged = false;
      await _ensureConnected();
      final socket = _socket;
      if (socket == null) {
        throw ModbusTcpException('not connected');
      }

      final txId = _nextTransactionId();
      final completer = Completer<Uint8List>();
      _activeTransactionId = txId;
      _activeRequest = completer;
      final adu = _buildAdu(txId: txId, unitId: unitId, pdu: pdu);
      _trace(
        'request start req=$requestId conn=$_connectionId tx=$txId '
        'fc=$fc start=$startAddress size=$qtyOrValueCount',
      );

      try {
        socket.add(adu);
        await socket.flush();
      } catch (e) {
        _clearActiveRequest();
        await disconnect();
        _trace(
          'request finish req=$requestId conn=$_connectionId tx=$txId '
          'result=send_error duration_ms=${stopwatch.elapsedMilliseconds} '
          'error=$e',
        );
        finishLogged = true;
        rethrow;
      }

      try {
        final response = await completer.future.timeout(
          responseTimeout,
          onTimeout: () {
            _consecutiveTimeouts += 1;
            final error = ModbusTcpException(
              'response timeout ($_consecutiveTimeouts consecutive)',
            );
            _failActiveRequest(error);
            _trace(
              'request finish req=$requestId conn=$_connectionId tx=$txId '
              'result=response_timeout duration_ms=${stopwatch.elapsedMilliseconds} '
              'streak=$_consecutiveTimeouts',
            );
            finishLogged = true;
            if (_consecutiveTimeouts >=
                maxConsecutiveTimeoutsBeforeDisconnect) {
              unawaited(disconnect());
            }
            throw error;
          },
        );
        _trace(
          'request finish req=$requestId conn=$_connectionId tx=$txId '
          'result=ok duration_ms=${stopwatch.elapsedMilliseconds}',
        );
        finishLogged = true;
        return response;
      } catch (e) {
        if (!finishLogged) {
          _trace(
            'request finish req=$requestId conn=$_connectionId tx=$txId '
            'result=error duration_ms=${stopwatch.elapsedMilliseconds} error=$e',
          );
        }
        rethrow;
      } finally {
        _clearActiveRequest();
      }
    });
    _requestChain = operation.then((_) {}, onError: (_) {});
    return operation;
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
      final pending = _activeRequest;
      if (pending == null || pending.isCompleted) {
        continue;
      }
      if (_activeTransactionId != txId) {
        continue;
      }
      _consecutiveTimeouts = 0;
      if (pdu.isNotEmpty && (pdu[0] & 0x80) != 0) {
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

  Future<void> _ensureConnected() async {
    if (_socket != null) {
      return;
    }
    final host = _lastHost;
    final port = _lastPort;
    if (host == null || port == null) {
      throw ModbusTcpException('not connected');
    }
    await connect(host, port);
  }

  int _normalizeAddress(int address) {
    if (address < 0) {
      throw ModbusTcpException('address must be >= 0');
    }
    switch (addressMode) {
      case ModbusAddressMode.zeroBased:
        return address;
      case ModbusAddressMode.style4xxxx:
        if (address < 40001 || address > 49999) {
          throw ModbusTcpException(
            '4xxxx addressing requires literal 4xxxx address, got $address',
          );
        }
        return address;
    }
  }

  int _nextTransactionId() {
    final value = _transactionId & 0xFFFF;
    _transactionId = (_transactionId + 1) & 0xFFFF;
    return value;
  }

  void _failActiveRequest(Object error) {
    final pending = _activeRequest;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(error);
    }
    _clearActiveRequest();
  }

  void _setConnected(bool value) {
    if (_connected == value) {
      return;
    }
    _connected = value;
    _connectionController.add(value);
  }

  void _clearActiveRequest() {
    _activeRequest = null;
    _activeTransactionId = null;
  }

  void _trace(String message) {
    traceSink?.call(message);
  }

  Future<void> dispose() async {
    await disconnect();
    await _connectionController.close();
  }
}
