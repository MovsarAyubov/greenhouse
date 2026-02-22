import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class ModbusService {
  SerialPort? _port;
  final _responseController = StreamController<List<int>>.broadcast();

  Stream<List<int>> get responseStream => _responseController.stream;

  bool get isConnected => _port != null && _port!.isOpen;

  // Connect to a serial port
  Future<void> connect(String portName) async {
    if (isConnected) await disconnect();

    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      SerialPort? tempPort;
      try {
        tempPort = SerialPort(portName);
        if (!tempPort.openReadWrite()) {
          final error = SerialPort.lastError;
          // specific check for "Operation successfully completed" (errno 0) on Windows
          // which actually means "Port locked" in some contexts or driver issues
          if (error != null) {
            print('Attempt ${retryCount + 1} failed. Error: $error');
          }
          // If we failed but strictly speaking errno=0, it might be a temporary OS lock.
          // Throwing to trigger retry catch block below (or internal loop logic)
          throw Exception('Failed to open port $portName. Last error: $error');
        }

        _port = tempPort;

        // Configure port (Standard Modbus settings: 9600, 8, N, 1)
        final config = SerialPortConfig();
        config.baudRate = 9600;
        config.bits = 8;
        config.parity = SerialPortParity.none;
        config.stopBits = 1;
        config.setFlowControl(SerialPortFlowControl.none);
        tempPort.config = config;

        // Start listening
        final reader = SerialPortReader(tempPort);
        reader.stream.listen((data) {
          _responseController.add(data);
        });

        print('Connected to $portName');
        return; // Success
      } catch (e) {
        // Ensure we dispose the temp port if we didn't successfully assign it
        if (tempPort != null && _port != tempPort) {
          tempPort.dispose();
        }

        print('Connection attempt ${retryCount + 1} failed: $e');
        retryCount++;
        if (retryCount >= maxRetries) {
          print('All connection attempts failed.');
          rethrow;
        }
        print('Retrying in 1 second...');
        await Future.delayed(const Duration(milliseconds: 1000));
      }
    }
  }

  Future<void> disconnect() async {
    if (_port != null) {
      try {
        _port!.close();
        _port!.dispose();
      } catch (e) {
        print('Error disconnecting: $e'); // Swallow error on close
      }
      _port = null;
    }
  }

  // Read Holding Registers (Function 03)
  Future<List<int>> readHoldingRegisters(int address, int count) async {
    if (!isConnected) throw Exception('Not connected');

    final frame = <int>[
      0x01, // Slave Address
      0x03, // Function Code
      (address >> 8) & 0xFF,
      address & 0xFF,
      (count >> 8) & 0xFF,
      count & 0xFF,
    ];

    final crc = _calculateCRC(frame);
    frame.add(crc & 0xFF);
    frame.add((crc >> 8) & 0xFF);

    _send(Uint8List.fromList(frame));

    // Wait for response with buffering
    final expectedLength = 5 + count * 2;
    final buffer = <int>[];

    // Create a temporary subscription to accumulate data
    late final StreamSubscription<List<int>> subscription;
    final completer = Completer<List<int>>();

    // Timer for timeout
    final timer = Timer(const Duration(seconds: 3), () {
      if (!completer.isCompleted) {
        completer.completeError(
          Exception(
            'Read timeout. Buffer: ${buffer.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')} (Length: ${buffer.length}/$expectedLength)',
          ),
        );
      }
    });

    subscription = _responseController.stream.listen((data) {
      print(
        'RX chunk: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );
      buffer.addAll(data);
      print(
        'Buffer: ${buffer.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')} (Need $expectedLength)',
      );

      // Check for Exception Response (Function Code + 0x80)
      if (buffer.length >= 2 && (buffer[1] & 0x80) != 0) {
        if (buffer.length >= 5) {
          final exceptionCode = buffer[2];
          final msg = _getModbusExceptionMessage(exceptionCode);
          if (!completer.isCompleted) {
            completer.completeError(
              Exception(
                'Modbus Exception: $msg (Code: 0x${exceptionCode.toRadixString(16)})',
              ),
            );
          }
        }
        return;
      }

      if (buffer.length >= expectedLength) {
        if (!completer.isCompleted) {
          completer.complete(buffer);
        }
      }
    });

    try {
      final response =
          await completer.future; // This handles the timeout error propagation
      timer.cancel();
      await subscription.cancel();

      // TODO: Validate CRC (check last 2 bytes vs calculated CRC of the rest)

      if (response.length < expectedLength) {
        throw Exception(
          'Invalid response length: ${response.length}, expected: $expectedLength',
        );
      }

      final data = <int>[];
      for (int i = 0; i < count; i++) {
        // Data starts at index 3
        final val = (response[3 + i * 2] << 8) | response[4 + i * 2];
        data.add(val);
      }
      return data;
    } catch (e) {
      timer.cancel();
      await subscription.cancel();
      print('Read error: $e');
      return [];
    }
  }

  // Write a single coil (Function 05)
  Future<void> writeCoil(int address, bool value) async {
    if (!isConnected) return;

    final frame = <int>[
      0x01, // Slave Address
      0x05, // Function Code
      (address >> 8) & 0xFF,
      address & 0xFF,
      value ? 0xFF : 0x00,
      0x00,
    ];

    final crc = _calculateCRC(frame);
    frame.add(crc & 0xFF);
    frame.add((crc >> 8) & 0xFF);

    _send(Uint8List.fromList(frame));
  }

  // Write a single register (Function 06)
  Future<void> writeRegister(int address, int value) async {
    if (!isConnected) return;

    final frame = <int>[
      0x01, // Slave Address
      0x06, // Function Code
      (address >> 8) & 0xFF,
      address & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];

    final crc = _calculateCRC(frame);
    frame.add(crc & 0xFF);
    frame.add((crc >> 8) & 0xFF);

    _send(Uint8List.fromList(frame));
  }

  void _send(Uint8List data) {
    if (_port != null) {
      try {
        if (!_port!.isOpen) {
          print('Warning: Port is closed, attempting to reopen...');
          if (!_port!.openReadWrite()) {
            print('Failed to reopen port.');
            return;
          }
        }

        final bytesWritten = _port!.write(data);
        print(
          'Sent ($bytesWritten bytes): ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}',
        );
      } catch (e) {
        print('Error sending data: $e');
      }
    }
  }

  int _calculateCRC(List<int> data) {
    int crc = 0xFFFF;
    for (int byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x0001) != 0) {
          crc >>= 1;
          crc ^= 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc;
  }

  void dispose() {
    disconnect();
    _responseController.close();
  }

  String _getModbusExceptionMessage(int code) {
    switch (code) {
      case 0x01:
        return 'Illegal Function';
      case 0x02:
        return 'Illegal Data Address';
      case 0x03:
        return 'Illegal Data Value';
      case 0x04:
        return 'Slave Device Failure';
      case 0x05:
        return 'Acknowledge';
      case 0x06:
        return 'Slave Device Busy';
      case 0x08:
        return 'Memory Parity Error';
      case 0x0A:
        return 'Gateway Path Unavailable';
      case 0x0B:
        return 'Gateway Target Device Failed to Respond';
      default:
        return 'Unknown Exception';
    }
  }
}
