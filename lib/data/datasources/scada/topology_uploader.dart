import 'dart:math';
import 'dart:typed_data';

import 'modbus_tcp_client.dart';
import 'register_map.dart';

class TopologyUploadChunk {
  const TopologyUploadChunk({
    required this.submitToken,
    required this.chunkIndex,
    required this.chunkWords,
    required this.flags,
    required this.totalSizeBytes,
    required this.chunkCrc32,
    required this.generation,
    required this.chunkDataWords,
  });

  final int submitToken;
  final int chunkIndex;
  final int chunkWords;
  final int flags;
  final int totalSizeBytes;
  final int chunkCrc32;
  final int generation;
  final List<int> chunkDataWords;
}

class TopologyUploadSummary {
  const TopologyUploadSummary({
    required this.chunksUploaded,
    required this.activeFlags,
    required this.activeGeneration,
    required this.activeSizeBytes,
  });

  final int chunksUploaded;
  final int activeFlags;
  final int activeGeneration;
  final int activeSizeBytes;
}

class TopologyUploader {
  TopologyUploader({
    required ModbusTcpClient client,
    required RegisterMap registerMap,
  }) : _client = client,
       _registerMap = registerMap;

  final ModbusTcpClient _client;
  final RegisterMap _registerMap;

  static const int resetFlag = 0x0002;
  static const int commitFlag = 0x0001;

  List<TopologyUploadChunk> buildChunks({
    required Uint8List blob,
    required int generation,
    required int startToken,
  }) {
    final chunkBytes = _registerMap.topologyChunkWordsMax * 2;
    final totalChunks = max(1, (blob.length + chunkBytes - 1) ~/ chunkBytes);
    final chunks = <TopologyUploadChunk>[];
    for (var index = 0; index < totalChunks; index++) {
      final offset = index * chunkBytes;
      final end = min(blob.length, offset + chunkBytes);
      final chunkBytesSlice = blob.sublist(offset, end);
      final words = _bytesToWords(chunkBytesSlice);
      var flags = 0;
      if (index == 0) {
        flags |= resetFlag;
      }
      if (index == totalChunks - 1) {
        flags |= commitFlag;
      }
      chunks.add(
        TopologyUploadChunk(
          submitToken: (startToken + index) & 0xFFFF,
          chunkIndex: index,
          chunkWords: words.length,
          flags: flags,
          totalSizeBytes: blob.length,
          chunkCrc32: Crc32.compute(chunkBytesSlice),
          generation: generation,
          chunkDataWords: words,
        ),
      );
    }
    return chunks;
  }

  Future<TopologyUploadSummary> upload({
    required Uint8List blob,
    required int generation,
    required int startToken,
    required Duration pollInterval,
    required Duration chunkTimeout,
    required Duration commitTimeout,
  }) async {
    final chunks = buildChunks(
      blob: blob,
      generation: generation,
      startToken: startToken,
    );
    for (final chunk in chunks) {
      final meta = <int>[
        chunk.chunkIndex & 0xFFFF,
        chunk.chunkWords & 0xFFFF,
        (chunk.totalSizeBytes >> 16) & 0xFFFF,
        chunk.totalSizeBytes & 0xFFFF,
        (chunk.chunkCrc32 >> 16) & 0xFFFF,
        chunk.chunkCrc32 & 0xFFFF,
        chunk.flags & 0xFFFF,
        (chunk.generation >> 16) & 0xFFFF,
        chunk.generation & 0xFFFF,
      ];
      await _client.writeMultipleRegisters(
        unitId: _registerMap.unitId,
        startAddress: _registerMap.topologyBase +
            _registerMap.topologyReqChunkIndexOffset,
        values: meta,
      );
      if (chunk.chunkDataWords.isNotEmpty) {
        await _client.writeMultipleRegisters(
          unitId: _registerMap.unitId,
          startAddress:
              _registerMap.topologyBase + _registerMap.topologyChunkDataOffset,
          values: chunk.chunkDataWords,
        );
      }
      await _client.writeSingleRegister(
        unitId: _registerMap.unitId,
        address:
            _registerMap.topologyBase + _registerMap.topologySubmitTokenOffset,
        value: chunk.submitToken,
      );
      await _waitForResult(
        token: chunk.submitToken,
        expectApplied: (chunk.flags & commitFlag) != 0,
        pollInterval: pollInterval,
        timeout: (chunk.flags & commitFlag) != 0 ? commitTimeout : chunkTimeout,
      );
    }
    final active = await _client.readHoldingRegisters(
      unitId: _registerMap.unitId,
      startAddress:
          _registerMap.topologyBase + _registerMap.topologyActiveFlagsOffset,
      count: 7,
    );
    return TopologyUploadSummary(
      chunksUploaded: chunks.length,
      activeFlags: active[0] & 0xFFFF,
      activeGeneration: ((active[3] & 0xFFFF) << 16) | (active[4] & 0xFFFF),
      activeSizeBytes: ((active[5] & 0xFFFF) << 16) | (active[6] & 0xFFFF),
    );
  }

  Future<void> _waitForResult({
    required int token,
    required bool expectApplied,
    required Duration pollInterval,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final regs = await _client.readHoldingRegisters(
        unitId: _registerMap.unitId,
        startAddress:
            _registerMap.topologyBase + _registerMap.topologyResultCodeOffset,
        count: 2,
      );
      final resultCode = regs[0] & 0xFFFF;
      final resultToken = regs[1] & 0xFFFF;
      if (resultToken != token) {
        await Future<void>.delayed(pollInterval);
        continue;
      }
      if (expectApplied && resultCode == _registerMap.topologyResultApplied) {
        return;
      }
      if (!expectApplied &&
          (resultCode == _registerMap.topologyResultQueued ||
              resultCode == _registerMap.topologyResultApplied)) {
        return;
      }
      throw StateError('Topology upload rejected: $resultCode');
    }
    throw StateError('Topology upload timeout for token=$token');
  }

  List<int> _bytesToWords(Uint8List bytes) {
    final out = <int>[];
    for (var index = 0; index < bytes.length; index += 2) {
      final hi = bytes[index] & 0xFF;
      final lo = index + 1 < bytes.length ? bytes[index + 1] & 0xFF : 0;
      out.add((hi << 8) | lo);
    }
    return out;
  }
}

class Crc32 {
  static final List<int> _table = List<int>.generate(256, _buildTableEntry);

  static int compute(List<int> bytes) {
    var crc = 0xFFFFFFFF;
    for (final byte in bytes) {
      final lookup = (crc ^ (byte & 0xFF)) & 0xFF;
      crc = _table[lookup] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static int _buildTableEntry(int index) {
    var value = index;
    for (var bit = 0; bit < 8; bit++) {
      if ((value & 1) != 0) {
        value = 0xEDB88320 ^ (value >> 1);
      } else {
        value >>= 1;
      }
    }
    return value & 0xFFFFFFFF;
  }
}
