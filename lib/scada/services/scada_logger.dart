import 'dart:io';

import '../models/scada_models.dart';

class ScadaLogger {
  File? _telemetryFile;
  File? _alarmFile;

  Future<void> init() async {
    final dir = Directory('${Directory.current.path}${Platform.pathSeparator}logs');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _telemetryFile = File('${dir.path}${Platform.pathSeparator}telemetry.csv');
    _alarmFile = File('${dir.path}${Platform.pathSeparator}alarms.csv');

    if (!(_telemetryFile!.existsSync())) {
      await _telemetryFile!.writeAsString(
        'time,zone,sensor_idx,sensor_value,online,stale\n',
      );
    }
    if (!(_alarmFile!.existsSync())) {
      await _alarmFile!.writeAsString(
        'time,zone,alarm_type,event,message\n',
      );
    }
  }

  Future<void> logZone(ZoneState zone) async {
    final file = _telemetryFile;
    if (file == null) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    final buffer = StringBuffer();
    for (var i = 0; i < zone.sensors.length; i++) {
      buffer.writeln(
        '$now,${zone.zoneId},$i,${zone.sensors[i].toStringAsFixed(2)},${zone.online ? 1 : 0},${zone.stale ? 1 : 0}',
      );
    }
    await file.writeAsString(buffer.toString(), mode: FileMode.append);
  }

  Future<void> logAlarm(
    AlarmEntry alarm, {
    required String event,
  }) async {
    final file = _alarmFile;
    if (file == null) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    await file.writeAsString(
      '$now,${alarm.zoneId},${alarm.type.name},$event,${_sanitizeCsv(alarm.message)}\n',
      mode: FileMode.append,
    );
  }

  String _sanitizeCsv(String source) =>
      source.replaceAll(',', ' ').replaceAll('\n', ' ').trim();
}
