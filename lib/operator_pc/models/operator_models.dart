import 'dart:typed_data';

import '../services/protocol.dart';

enum SensorQuality { ok, stale, fault, offline }

enum Severity { info, warn, alarm, crit }

const int kChannelsPerBlock = 9;
const List<String> kChannelNames = <String>[
  'AIR_TEMP',
  'AIR_HUM',
  'WATER_RAIL',
  'WATER_GROW',
  'WATER_UNDERTRAY',
  'WATER_UPPER_HEAT',
  'WINDOWS_POS_A',
  'WINDOWS_POS_B',
  'CURTAIN_POS',
];

int sensorIdToBlockNo(int sensorId) => (sensorId ~/ kChannelsPerBlock) + 1;
int sensorIdToChannelIndex(int sensorId) => sensorId % kChannelsPerBlock;
String sensorIdToChannelName(int sensorId) =>
    kChannelNames[sensorIdToChannelIndex(sensorId)];
bool isMappedSource(int source) => source >= 0 && source < kSensorCount;
String displayChannelName(int sensorId) =>
    isMappedSource(sensorId) ? sensorIdToChannelName(sensorId) : 'UNKNOWN';
String displayBlockLabel(int sensorId) =>
    isMappedSource(sensorId) ? '${sensorIdToBlockNo(sensorId)}' : '-';

String decodeSource(int source) {
  if (!isMappedSource(source)) {
    return 'Unknown source';
  }
  final blockNo = sensorIdToBlockNo(source);
  final channelName = sensorIdToChannelName(source);
  return 'Block $blockNo / $channelName';
}

class BlockLayoutItem {
  const BlockLayoutItem({
    required this.blockNo,
    required this.slaveId,
    required this.startReg,
    required this.sensorCount,
    required this.sensorBase,
  });

  final int blockNo;
  final int slaveId;
  final int startReg;
  final int sensorCount;
  final int sensorBase;
}

class SensorPoint {
  SensorPoint({
    required this.id,
    required this.value,
    required this.quality,
    required this.timestamp,
  });

  final int id;
  final double value;
  final SensorQuality quality;
  final DateTime timestamp;
}

class EventItem {
  EventItem({
    required this.eventId,
    required this.severity,
    required this.code,
    required this.source,
    required this.value,
    required this.timestamp,
    required this.acked,
  });

  final int eventId;
  final Severity severity;
  final int code;
  final int source;
  final double value;
  final DateTime timestamp;
  final bool acked;

  EventItem copyWith({bool? acked}) => EventItem(
    eventId: eventId,
    severity: severity,
    code: code,
    source: source,
    value: value,
    timestamp: timestamp,
    acked: acked ?? this.acked,
  );
}

class MasterStatus {
  MasterStatus({
    required this.connected,
    required this.rttMs,
    required this.lastSnapshotAt,
    required this.lastSnapshotId,
    required this.activeConfigVersion,
    required this.lastErrorCode,
    required this.tcpConnectCount,
    required this.tcpDisconnectCount,
    required this.controlMode,
    required this.autonomousReason,
    required this.lastMasterSeenMs,
  });

  final bool connected;
  final int rttMs;
  final DateTime? lastSnapshotAt;
  final int lastSnapshotId;
  final int activeConfigVersion;
  final int lastErrorCode;
  final int tcpConnectCount;
  final int tcpDisconnectCount;
  final int controlMode;
  final int autonomousReason;
  final int lastMasterSeenMs;

  MasterStatus copyWith({
    bool? connected,
    int? rttMs,
    DateTime? lastSnapshotAt,
    int? lastSnapshotId,
    int? activeConfigVersion,
    int? lastErrorCode,
    int? tcpConnectCount,
    int? tcpDisconnectCount,
    int? controlMode,
    int? autonomousReason,
    int? lastMasterSeenMs,
  }) {
    return MasterStatus(
      connected: connected ?? this.connected,
      rttMs: rttMs ?? this.rttMs,
      lastSnapshotAt: lastSnapshotAt ?? this.lastSnapshotAt,
      lastSnapshotId: lastSnapshotId ?? this.lastSnapshotId,
      activeConfigVersion: activeConfigVersion ?? this.activeConfigVersion,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      tcpConnectCount: tcpConnectCount ?? this.tcpConnectCount,
      tcpDisconnectCount: tcpDisconnectCount ?? this.tcpDisconnectCount,
      controlMode: controlMode ?? this.controlMode,
      autonomousReason: autonomousReason ?? this.autonomousReason,
      lastMasterSeenMs: lastMasterSeenMs ?? this.lastMasterSeenMs,
    );
  }

  static MasterStatus initial() => MasterStatus(
    connected: false,
    rttMs: 0,
    lastSnapshotAt: null,
    lastSnapshotId: 0,
    activeConfigVersion: 0,
    lastErrorCode: 0,
    tcpConnectCount: 0,
    tcpDisconnectCount: 0,
    controlMode: 255,
    autonomousReason: 0,
    lastMasterSeenMs: 0,
  );
}

class SnapshotData {
  SnapshotData({
    required this.snapshotId,
    required this.timestampMs,
    required this.values,
    required this.quality,
  });

  final int snapshotId;
  final int timestampMs;
  final List<double> values;
  final List<SensorQuality> quality;

  static SnapshotData? tryParse(Uint8List payload) {
    if (payload.length < 8 + (kSensorCount * 4) + kSensorCount) {
      return null;
    }
    final d = ByteData.sublistView(payload);
    final snapshotId = d.getUint32(0, Endian.little);
    final timestampMs = d.getUint32(4, Endian.little);

    final values = <double>[];
    final quality = <SensorQuality>[];

    var offset = 8;
    for (var i = 0; i < kSensorCount; i++) {
      values.add(d.getFloat32(offset, Endian.little));
      offset += 4;
    }

    for (var i = 0; i < kSensorCount; i++) {
      quality.add(_qualityFromByte(payload[offset + i]));
    }

    return SnapshotData(
      snapshotId: snapshotId,
      timestampMs: timestampMs,
      values: values,
      quality: quality,
    );
  }
}

SensorQuality _qualityFromByte(int v) {
  switch (v) {
    case 0:
      return SensorQuality.ok;
    case 1:
      return SensorQuality.stale;
    case 2:
      return SensorQuality.fault;
    case 3:
      return SensorQuality.offline;
    default:
      return SensorQuality.fault;
  }
}

Severity severityFromByte(int v) {
  switch (v) {
    case 0:
      return Severity.info;
    case 1:
      return Severity.warn;
    case 2:
      return Severity.alarm;
    case 3:
      return Severity.crit;
    default:
      return Severity.warn;
  }
}
