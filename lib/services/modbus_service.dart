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

    try {
      final port = SerialPort(portName);
      if (!port.openReadWrite()) {
        final error = SerialPort.lastError;
        if (error != null) {
          throw Exception('Failed to open port $portName. Error: $error');
        }
        throw Exception('Failed to open port $portName. Unknown error.');
      }

      _port = port;

      // Configure port (Standard Modbus settings: 9600, 8, N, 1)
      final config = SerialPortConfig();
      config.baudRate = 9600;
      config.bits = 8;
      config.parity = SerialPortParity.none;
      config.stopBits = 1;
      config.setFlowControl(SerialPortFlowControl.none);
      port.config = config;

      // Start listening
      final reader = SerialPortReader(port);
      reader.stream.listen((data) {
        _responseController.add(data);
      });

      print('Connected to $portName');
    } catch (e) {
      print('Error connecting to $portName: $e');
      rethrow;
    }
  }

  Future<void> disconnect() async {
    if (_port != null) {
      _port!.close();
      _port!.dispose();
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

    // Wait for response (Simplified: just wait for next data chunk)
    // In real app, we need to buffer and parse based on expected length
    try {
      final response = await _responseController.stream.first.timeout(
        const Duration(seconds: 1),
      );
      // TODO: Validate CRC and parse response
      // Response: Addr, Func, ByteCount, Data..., CRC
      if (response.length < 5 + count * 2) {
        throw Exception('Invalid response length');
      }

      final data = <int>[];
      for (int i = 0; i < count; i++) {
        final val = (response[3 + i * 2] << 8) | response[4 + i * 2];
        data.add(val);
      }
      return data;
    } catch (e) {
      print('Read timeout or error: $e');
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
}
