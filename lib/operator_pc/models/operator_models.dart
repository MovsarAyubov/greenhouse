import 'dart:typed_data';

import '../services/protocol.dart';

enum SensorQuality { ok, stale, fault, offline }

enum Severity { info, warn, alarm, crit }

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
    required this.activeConfigVersion,
    required this.lastErrorCode,
  });

  final bool connected;
  final int rttMs;
  final DateTime? lastSnapshotAt;
  final int activeConfigVersion;
  final int lastErrorCode;

  MasterStatus copyWith({
    bool? connected,
    int? rttMs,
    DateTime? lastSnapshotAt,
    int? activeConfigVersion,
    int? lastErrorCode,
  }) {
    return MasterStatus(
      connected: connected ?? this.connected,
      rttMs: rttMs ?? this.rttMs,
      lastSnapshotAt: lastSnapshotAt ?? this.lastSnapshotAt,
      activeConfigVersion: activeConfigVersion ?? this.activeConfigVersion,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
    );
  }

  static MasterStatus initial() => MasterStatus(
    connected: false,
    rttMs: 0,
    lastSnapshotAt: null,
    activeConfigVersion: 0,
    lastErrorCode: 0,
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
