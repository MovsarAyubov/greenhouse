import 'dart:io';

<<<<<<< HEAD:lib/data/services/scada/scada_logger.dart
import 'package:greenhouse/domain/entities/scada/scada_models.dart';
=======
import '../models/topology_models.dart';
>>>>>>> client_transport_topology:lib/scada/services/scada_logger.dart

class ScadaLogger {
  File? _telemetryFile;
  File? _clientTraceFile;
  File? _scheduleTxFile;
  Future<void> _writeChain = Future<void>.value();

  Future<void> init() async {
    final dir = Directory(
      '${Directory.current.path}${Platform.pathSeparator}logs',
    );
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _telemetryFile = File('${dir.path}${Platform.pathSeparator}telemetry.csv');
    _clientTraceFile = File(
      '${dir.path}${Platform.pathSeparator}client_trace.csv',
    );
    _scheduleTxFile = File(
      '${dir.path}${Platform.pathSeparator}schedule_tx.csv',
    );

    if (!(_telemetryFile!.existsSync())) {
      await _telemetryFile!.writeAsString(
        'time,module_id,point_id,publish_index,value,quality,age_sec,flags\n',
      );
    }
    if (!(_clientTraceFile!.existsSync())) {
      await _clientTraceFile!.writeAsString('time,event\n');
    }
    if (!(_scheduleTxFile!.existsSync())) {
      await _scheduleTxFile!.writeAsString(
        'time,module_id,slave_id,event,operation,address,count,request_regs,response_regs,trigger,last_applied,last_result,last_io_err,message\n',
      );
    }
  }

  Future<void> logPoint({
    required int moduleId,
    required TopologyPoint point,
    required double value,
    required int quality,
    required int ageSec,
    required int flags,
  }) async {
    final file = _telemetryFile;
    if (file == null) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    await _append(
      file,
      '$now,$moduleId,${point.pointId},${point.publishIndex},'
      '${value.toStringAsFixed(3)},$quality,$ageSec,$flags\n',
    );
  }

  Future<void> logClientEvent(String event) async {
    final file = _clientTraceFile;
    if (file == null) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    await _append(file, '$now,${_sanitizeCsv(event)}\n');
  }

  Future<void> logScheduleTransaction({
    required int moduleId,
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
    await _append(
      file,
      '$now,$moduleId,$slaveId,${_sanitizeCsv(event)},${_sanitizeCsv(operation)},'
      '${address ?? ''},${count ?? ''},${_encodeRegs(requestRegs)},${_encodeRegs(responseRegs)},'
      '${trigger ?? ''},${lastAppliedTrigger ?? ''},${lastResult ?? ''},${lastIoErr ?? ''},'
      '${_sanitizeCsv(message ?? '')}\n',
    );
  }

  Future<void> _append(File file, String line) {
    _writeChain = _writeChain.catchError((_) {}).then((_) {
      return file.writeAsString(line, mode: FileMode.append);
    });
    return _writeChain;
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
