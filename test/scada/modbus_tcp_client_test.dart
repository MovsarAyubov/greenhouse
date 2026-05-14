import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/scada/services/modbus_tcp_client.dart';

void main() {
  test(
    'ModbusTcpClient keeps one request in flight per TCP connection',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final firstFrameSeen = Completer<void>();
      final secondFrameSeen = Completer<void>();
      final frames = <Uint8List>[];

      unawaited(() async {
        final socket = await server.first;
        final buffer = <int>[];
        socket.listen((chunk) async {
          buffer.addAll(chunk);
          while (buffer.length >= 7) {
            final header = Uint8List.fromList(buffer.sublist(0, 7));
            final data = ByteData.sublistView(header);
            final length = data.getUint16(4, Endian.big);
            final fullLength = 6 + length;
            if (buffer.length < fullLength) {
              return;
            }
            final frame = Uint8List.fromList(buffer.sublist(0, fullLength));
            buffer.removeRange(0, fullLength);
            frames.add(frame);
            if (frames.length == 1 && !firstFrameSeen.isCompleted) {
              firstFrameSeen.complete();
              await Future<void>.delayed(const Duration(milliseconds: 120));
              socket.add(_readResponse(frame, 0x1234));
              await socket.flush();
            } else if (frames.length == 2 && !secondFrameSeen.isCompleted) {
              secondFrameSeen.complete();
              socket.add(_readResponse(frame, 0x5678));
              await socket.flush();
            }
          }
        });
      }());

      final client = ModbusTcpClient(
        responseTimeout: const Duration(seconds: 2),
      );
      await client.connect('127.0.0.1', server.port);

      final first = client.readHoldingRegisters(
        unitId: 1,
        startAddress: 10,
        count: 1,
      );
      final second = client.readHoldingRegisters(
        unitId: 1,
        startAddress: 11,
        count: 1,
      );

      await firstFrameSeen.future;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(frames.length, 1);

      final firstRegs = await first;
      expect(firstRegs, const <int>[0x1234]);

      await secondFrameSeen.future.timeout(const Duration(seconds: 1));
      final secondRegs = await second;
      expect(secondRegs, const <int>[0x5678]);

      await client.dispose();
      await server.close();
    },
  );

  test('single timeout does not force reconnect', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    var acceptCount = 0;
    final secondFrameSeen = Completer<void>();

    unawaited(() async {
      final socket = await server.first;
      acceptCount += 1;
      final buffer = <int>[];
      var frameCount = 0;
      socket.listen((chunk) async {
        buffer.addAll(chunk);
        while (buffer.length >= 7) {
          final header = Uint8List.fromList(buffer.sublist(0, 7));
          final data = ByteData.sublistView(header);
          final length = data.getUint16(4, Endian.big);
          final fullLength = 6 + length;
          if (buffer.length < fullLength) {
            return;
          }
          final frame = Uint8List.fromList(buffer.sublist(0, fullLength));
          buffer.removeRange(0, fullLength);
          frameCount += 1;
          if (frameCount == 1) {
            await Future<void>.delayed(const Duration(milliseconds: 120));
            continue;
          }
          if (!secondFrameSeen.isCompleted) {
            secondFrameSeen.complete();
          }
          socket.add(_readResponse(frame, 0x2222));
          await socket.flush();
        }
      });
    }());

    final client = ModbusTcpClient(
      responseTimeout: const Duration(milliseconds: 50),
      maxConsecutiveTimeoutsBeforeDisconnect: 3,
    );
    await client.connect('127.0.0.1', server.port);

    await expectLater(
      client.readHoldingRegisters(unitId: 1, startAddress: 10, count: 1),
      throwsA(isA<ModbusTcpException>()),
    );

    final regs = await client.readHoldingRegisters(
      unitId: 1,
      startAddress: 11,
      count: 1,
    );
    await secondFrameSeen.future.timeout(const Duration(seconds: 1));

    expect(regs, const <int>[0x2222]);
    expect(acceptCount, 1);

    await client.dispose();
    await server.close();
  });

  test('reconnects after timeout-forced disconnect', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    var acceptCount = 0;
    final secondConnectionFrameSeen = Completer<void>();

    unawaited(() async {
      await for (final socket in server) {
        acceptCount += 1;
        final connectionNo = acceptCount;
        final buffer = <int>[];
        socket.listen((chunk) async {
          buffer.addAll(chunk);
          while (buffer.length >= 7) {
            final header = Uint8List.fromList(buffer.sublist(0, 7));
            final data = ByteData.sublistView(header);
            final length = data.getUint16(4, Endian.big);
            final fullLength = 6 + length;
            if (buffer.length < fullLength) {
              return;
            }
            final frame = Uint8List.fromList(buffer.sublist(0, fullLength));
            buffer.removeRange(0, fullLength);
            if (connectionNo == 1) {
              continue;
            }
            if (!secondConnectionFrameSeen.isCompleted) {
              secondConnectionFrameSeen.complete();
            }
            socket.add(_readResponse(frame, 0x3333));
            await socket.flush();
          }
        });
      }
    }());

    final client = ModbusTcpClient(
      responseTimeout: const Duration(milliseconds: 50),
      maxConsecutiveTimeoutsBeforeDisconnect: 1,
    );
    await client.connect('127.0.0.1', server.port);

    await expectLater(
      client.readHoldingRegisters(unitId: 1, startAddress: 10, count: 1),
      throwsA(isA<ModbusTcpException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final regs = await client.readHoldingRegisters(
      unitId: 1,
      startAddress: 11,
      count: 1,
    );
    await secondConnectionFrameSeen.future.timeout(const Duration(seconds: 1));

    expect(regs, const <int>[0x3333]);
    expect(acceptCount, greaterThanOrEqualTo(2));

    await client.dispose();
    await server.close();
  });
}

Uint8List _readResponse(Uint8List requestFrame, int value) {
  final requestHeader = ByteData.sublistView(requestFrame);
  final txId = requestHeader.getUint16(0, Endian.big);
  final unitId = requestFrame[6];
  final response = Uint8List(11);
  final data = ByteData.sublistView(response);
  data.setUint16(0, txId, Endian.big);
  data.setUint16(2, 0, Endian.big);
  data.setUint16(4, 5, Endian.big);
  response[6] = unitId;
  response[7] = 0x03;
  response[8] = 0x02;
  data.setUint16(9, value & 0xFFFF, Endian.big);
  return response;
}
