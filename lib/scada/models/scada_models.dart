enum ZoneMode { auto, manual, service }

enum AlarmType { offline, stale, invalidSensor, commandMismatch }

class ScadaConfig {
  const ScadaConfig({
    required this.masterIp,
    required this.masterPort,
    required this.pollPeriodMs,
    required this.staleThresholdSec,
    required this.logPeriodSec,
    required this.sensorNames,
    required this.outputNames,
  });

  final String masterIp;
  final int masterPort;
  final int pollPeriodMs;
  final int staleThresholdSec;
  final int logPeriodSec;
  final List<String> sensorNames;
  final List<String> outputNames;

  ScadaConfig copyWith({
    String? masterIp,
    int? masterPort,
    int? pollPeriodMs,
    int? staleThresholdSec,
    int? logPeriodSec,
    List<String>? sensorNames,
    List<String>? outputNames,
  }) {
    return ScadaConfig(
      masterIp: masterIp ?? this.masterIp,
      masterPort: masterPort ?? this.masterPort,
      pollPeriodMs: pollPeriodMs ?? this.pollPeriodMs,
      staleThresholdSec: staleThresholdSec ?? this.staleThresholdSec,
      logPeriodSec: logPeriodSec ?? this.logPeriodSec,
      sensorNames: sensorNames ?? this.sensorNames,
      outputNames: outputNames ?? this.outputNames,
    );
  }

  static ScadaConfig defaults() => ScadaConfig(
    masterIp: '192.168.50.20',
    masterPort: 502,
    pollPeriodMs: 1000,
    staleThresholdSec: 5,
    logPeriodSec: 10,
    sensorNames: List<String>.generate(9, (i) => 'Sensor ${i + 1}'),
    outputNames: List<String>.generate(16, (i) => 'Output ${i + 1}'),
  );
}

class ZoneState {
  const ZoneState({
    required this.zoneId,
    required this.sensors,
    required this.sensorValidMask,
    required this.outputs,
    required this.outputCommandMask,
    required this.mode,
    required this.setpoints,
    required this.online,
    required this.stale,
    required this.lastUpdate,
    required this.lastOkAgeSec,
    required this.errTimeout,
    required this.errCrc,
    required this.errException,
    required this.dataVersion,
    required this.lastAppliedTrigger,
    required this.lastPollMs,
  });

  final int zoneId;
  final List<double> sensors;
  final int sensorValidMask;
  final List<bool> outputs;
  final int outputCommandMask;
  final ZoneMode mode;
  final ZoneSetpoints setpoints;
  final bool online;
  final bool stale;
  final DateTime? lastUpdate;
  final int lastOkAgeSec;
  final int errTimeout;
  final int errCrc;
  final int errException;
  final int dataVersion;
  final int lastAppliedTrigger;
  final int lastPollMs;

  double get temperature => sensors.isNotEmpty ? sensors[0] : 0;
  double get humidity => sensors.length > 1 ? sensors[1] : 0;

  ZoneState copyWith({
    List<double>? sensors,
    int? sensorValidMask,
    List<bool>? outputs,
    int? outputCommandMask,
    ZoneMode? mode,
    ZoneSetpoints? setpoints,
    bool? online,
    bool? stale,
    DateTime? lastUpdate,
    int? lastOkAgeSec,
    int? errTimeout,
    int? errCrc,
    int? errException,
    int? dataVersion,
    int? lastAppliedTrigger,
    int? lastPollMs,
  }) {
    return ZoneState(
      zoneId: zoneId,
      sensors: sensors ?? this.sensors,
      sensorValidMask: sensorValidMask ?? this.sensorValidMask,
      outputs: outputs ?? this.outputs,
      outputCommandMask: outputCommandMask ?? this.outputCommandMask,
      mode: mode ?? this.mode,
      setpoints: setpoints ?? this.setpoints,
      online: online ?? this.online,
      stale: stale ?? this.stale,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      lastOkAgeSec: lastOkAgeSec ?? this.lastOkAgeSec,
      errTimeout: errTimeout ?? this.errTimeout,
      errCrc: errCrc ?? this.errCrc,
      errException: errException ?? this.errException,
      dataVersion: dataVersion ?? this.dataVersion,
      lastAppliedTrigger: lastAppliedTrigger ?? this.lastAppliedTrigger,
      lastPollMs: lastPollMs ?? this.lastPollMs,
    );
  }

  static ZoneState initial(int zoneId) => ZoneState(
    zoneId: zoneId,
    sensors: List<double>.filled(9, 0),
    sensorValidMask: 0,
    outputs: List<bool>.filled(16, false),
    outputCommandMask: 0,
    mode: ZoneMode.auto,
    setpoints: ZoneSetpoints.defaults(),
    online: false,
    stale: true,
    lastUpdate: null,
    lastOkAgeSec: 0,
    errTimeout: 0,
    errCrc: 0,
    errException: 0,
    dataVersion: 0,
    lastAppliedTrigger: 0,
    lastPollMs: 0,
  );
}

class AlarmEntry {
  const AlarmEntry({
    required this.id,
    required this.zoneId,
    required this.type,
    required this.message,
    required this.raisedAt,
    required this.acknowledged,
    this.clearedAt,
  });

  final String id;
  final int zoneId;
  final AlarmType type;
  final String message;
  final DateTime raisedAt;
  final DateTime? clearedAt;
  final bool acknowledged;

  bool get isActive => clearedAt == null;

  AlarmEntry copyWith({
    DateTime? clearedAt,
    bool? acknowledged,
  }) {
    return AlarmEntry(
      id: id,
      zoneId: zoneId,
      type: type,
      message: message,
      raisedAt: raisedAt,
      clearedAt: clearedAt ?? this.clearedAt,
      acknowledged: acknowledged ?? this.acknowledged,
    );
  }
}

class TrendPoint {
  const TrendPoint({
    required this.time,
    required this.zoneId,
    required this.sensorIndex,
    required this.value,
  });

  final DateTime time;
  final int zoneId;
  final int sensorIndex;
  final double value;
}

class ZoneCommandDraft {
  const ZoneCommandDraft({
    required this.mode,
    required this.setpoints,
    required this.outputsManual,
  });

  final ZoneMode mode;
  final ZoneSetpoints setpoints;
  final List<bool> outputsManual;

  static ZoneCommandDraft fromZone(ZoneState zone) => ZoneCommandDraft(
    mode: zone.mode,
    setpoints: zone.setpoints,
    outputsManual: List<bool>.from(zone.outputs),
  );
}

class ZoneSetpoints {
  const ZoneSetpoints({
    required this.setTemp,
    required this.setHum,
    required this.hystTemp,
    required this.hystHum,
    required this.minOnSec,
    required this.minOffSec,
  });

  final double setTemp;
  final double setHum;
  final double hystTemp;
  final double hystHum;
  final int minOnSec;
  final int minOffSec;

  ZoneSetpoints copyWith({
    double? setTemp,
    double? setHum,
    double? hystTemp,
    double? hystHum,
    int? minOnSec,
    int? minOffSec,
  }) {
    return ZoneSetpoints(
      setTemp: setTemp ?? this.setTemp,
      setHum: setHum ?? this.setHum,
      hystTemp: hystTemp ?? this.hystTemp,
      hystHum: hystHum ?? this.hystHum,
      minOnSec: minOnSec ?? this.minOnSec,
      minOffSec: minOffSec ?? this.minOffSec,
    );
  }

  static ZoneSetpoints defaults() => const ZoneSetpoints(
    setTemp: 22.0,
    setHum: 65.0,
    hystTemp: 1.0,
    hystHum: 3.0,
    minOnSec: 10,
    minOffSec: 10,
  );
}
