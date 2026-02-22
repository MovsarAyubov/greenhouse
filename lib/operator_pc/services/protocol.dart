import 'dart:typed_data';

const int kProtoMagic = 0xA55A;
const int kProtoVersion = 1;
const int kHeaderSize = 14;
const int kSensorCount = 150;

class MsgType {
  static const int hello = 1;
  static const int helloAck = 2;
  static const int heartbeat = 3;
  static const int statusReq = 4;
  static const int statusResp = 5;
  static const int snapshot = 6;
  static const int event = 7;
  static const int eventAck = 8;
  static const int getConfigReq = 9;
  static const int getConfigResp = 10;
  static const int setpointsPut = 11;
  static const int setpointsValidateAck = 12;
  static const int setpointsApplyReq = 13;
  static const int setpointsApplyAck = 14;
}

class ProtocolFrame {
  ProtocolFrame({
    required this.msgType,
    required this.seq,
    required this.payload,
  });

  final int msgType;
  final int seq;
  final Uint8List payload;
}

class FrameCodec {
  FrameCodec({this.protoVersion = kProtoVersion});

  final int protoVersion;

  Uint8List encode({
    required int msgType,
    required int seq,
    required Uint8List payload,
  }) {
    final bytes = Uint8List(kHeaderSize + payload.length);
    final h = ByteData.sublistView(bytes, 0, kHeaderSize);
    h.setUint16(0, kProtoMagic, Endian.little);
    h.setUint8(2, protoVersion);
    h.setUint8(3, msgType);
    h.setUint32(4, seq, Endian.little);
    h.setUint16(8, payload.length, Endian.little);
    h.setUint32(10, crc32(payload), Endian.little);
    bytes.setRange(kHeaderSize, bytes.length, payload);
    return bytes;
  }
}

class FrameParser {
  final List<int> _buffer = <int>[];

  List<ProtocolFrame> addBytes(Uint8List bytes) {
    _buffer.addAll(bytes);
    final frames = <ProtocolFrame>[];

    while (_buffer.length >= kHeaderSize) {
      final head = Uint8List.fromList(_buffer.sublist(0, kHeaderSize));
      final h = ByteData.sublistView(head);

      if (h.getUint16(0, Endian.little) != kProtoMagic) {
        _buffer.removeAt(0);
        continue;
      }

      final protoVer = h.getUint8(2);
      if (protoVer != kProtoVersion) {
        _buffer.removeAt(0);
        continue;
      }

      final msgType = h.getUint8(3);
      final seq = h.getUint32(4, Endian.little);
      final len = h.getUint16(8, Endian.little);
      final crc = h.getUint32(10, Endian.little);
      final fullLen = kHeaderSize + len;
      if (_buffer.length < fullLen) {
        break;
      }

      final payload = Uint8List.fromList(_buffer.sublist(kHeaderSize, fullLen));
      _buffer.removeRange(0, fullLen);

      if (crc32(payload) != crc) {
        continue;
      }

      frames.add(ProtocolFrame(msgType: msgType, seq: seq, payload: payload));
    }

    return frames;
  }
}

int crc32(Uint8List data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      if ((crc & 1) == 1) {
        crc = (crc >> 1) ^ 0xEDB88320;
      } else {
        crc = crc >> 1;
      }
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
