import 'dart:io';

import '../models/scada_models.dart';

class ScadaLogger {
  File? _telemetryFile;
  File? _alarmFile;
  File? _clientTraceFile;
  File? _scheduleTxFile;

  Future<void> init() async {
    final dir = Directory(
      '${Directory.current.path}${Platform.pathSeparator}logs',
    );
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _telemetryFile = File('${dir.path}${Platform.pathSeparator}telemetry.csv');
    _alarmFile = File('${dir.path}${Platform.pathSeparator}alarms.csv');
    _clientTraceFile = File(
      '${dir.path}${Platform.pathSeparator}client_trace.csv',
    );
    _scheduleTxFile = File(
      '${dir.path}${Platform.pathSeparator}schedule_tx.csv',
    );

    if (!(_telemetryFile!.existsSync())) {
      await _telemetryFile!.writeAsString(
        'time,zone,sensor_idx,sensor_value,online,stale\n',
      );
    }
    if (!(_alarmFile!.existsSync())) {
      await _alarmFile!.writeAsString('time,zone,alarm_type,event,message\n');
    }
    if (!(_clientTraceFile!.existsSync())) {
      await _clientTraceFile!.writeAsString('time,event\n');
    }
    if (!(_scheduleTxFile!.existsSync())) {
      await _scheduleTxFile!.writeAsString(
        'time,slave_id,event,operation,address,count,request_regs,response_regs,trigger,last_applied,last_result,last_io_err,message\n',
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

  Future<void> logAlarm(AlarmEntry alarm, {required String event}) async {
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

  Future<void> logClientEvent(String event) async {
    final file = _clientTraceFile;
    if (file == null) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    await file.writeAsString(
      '$now,${_sanitizeCsv(event)}\n',
      mode: FileMode.append,
    );
  }

  Future<void> logScheduleTransaction({
    required int slaveId,
    required String event,
    required String operation,
    int? address,
    int? count,
    List<int>? requestRegs,
    List<int>? responseRegs,
    int? trigger,
    int? lastAppliedTrigger,
    int? lastResult,
    int? lastIoErr,
    String? message,
  }) async {
    final file = _scheduleTxFile;
    if (file == null) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    await file.writeAsString(
      '$now,$slaveId,${_sanitizeCsv(event)},${_sanitizeCsv(operation)},'
      '${address ?? ''},${count ?? ''},${_encodeRegs(requestRegs)},${_encodeRegs(responseRegs)},'
      '${trigger ?? ''},${lastAppliedTrigger ?? ''},${lastResult ?? ''},${lastIoErr ?? ''},'
      '${_sanitizeCsv(message ?? '')}\n',
      mode: FileMode.append,
    );
  }

  String _encodeRegs(List<int>? values) {
    if (values == null || values.isEmpty) {
      return '';
    }
    return values.map((v) => (v & 0xFFFF).toString()).join('|');
  }

  String _sanitizeCsv(String source) =>
      source.replaceAll(',', ' ').replaceAll('\n', ' ').trim();
}
