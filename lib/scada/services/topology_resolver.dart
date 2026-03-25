import '../models/topology_models.dart';

class ScheduleCommandContract {
  const ScheduleCommandContract({
    required this.cmdProfileId,
    required this.timeoutMs,
  });

  final int cmdProfileId;
  final int timeoutMs;
}

class TopologyResolver {
  TopologyResolver(this.manifest)
    : _modulesById = {
        for (final module in manifest.modules) module.moduleId: module,
      },
      _pointsByModuleId = _groupPoints(manifest.points),
      _commandsByModuleId = _groupCommands(manifest.commands);

  final TopologyManifest manifest;
  final Map<int, TopologyModule> _modulesById;
  final Map<int, List<TopologyPoint>> _pointsByModuleId;
  final Map<int, List<TopologyCommand>> _commandsByModuleId;

  List<TopologyModule> get zoneModules => manifest.modules
      .where((module) => module.isZone)
      .toList(growable: false)
    ..sort((a, b) => a.zoneId.compareTo(b.zoneId));

  List<TopologyModule> get weatherModules => manifest.modules
      .where((module) => module.isWeather)
      .toList(growable: false)
    ..sort((a, b) => a.moduleId.compareTo(b.moduleId));

  TopologyModule? moduleById(int moduleId) => _modulesById[moduleId];

  List<TopologyPoint> pointsForModule(int moduleId) {
    final points = _pointsByModuleId[moduleId] ?? const <TopologyPoint>[];
    return List<TopologyPoint>.from(points)
      ..sort((a, b) => a.publishIndex.compareTo(b.publishIndex));
  }

  TopologyPoint? pointBySemantic({
    required int moduleId,
    required String semanticName,
  }) {
    for (final point in pointsForModule(moduleId)) {
      if (point.semanticName == semanticName) {
        return point;
      }
    }
    return null;
  }

  ScheduleCommandContract? scheduleContractForModule(int moduleId) {
    final module = moduleById(moduleId);
    if (module == null || !module.isZone || module.slaveId <= 0) {
      return null;
    }
    final commands = _commandsByModuleId[moduleId] ?? const <TopologyCommand>[];
    for (final command in commands) {
      final isLightSetpointsContract =
          command.cmdId >= 5000 &&
          command.fc == 16 &&
          command.startReg == 110 &&
          command.maxRegCount <= 13 &&
          command.payloadOffset == 0 &&
          (command.cmdKind == 'generic' || command.cmdKind == 'schedule');
      if (isLightSetpointsContract) {
        return ScheduleCommandContract(
          cmdProfileId: command.cmdId,
          timeoutMs: command.timeoutMs,
        );
      }
    }
    final cmdProfileId = _knownCmdProfileIdForModule(module);
    if (cmdProfileId == null) {
      return null;
    }
    return ScheduleCommandContract(cmdProfileId: cmdProfileId, timeoutMs: 3000);
  }

  bool hasScheduleContract(int moduleId) =>
      scheduleContractForModule(moduleId) != null;

  int? _knownCmdProfileIdForModule(TopologyModule module) {
    if (module.moduleId == 101 && module.slaveId == 1) {
      return 5001;
    }
    if (module.moduleId == 102 && module.slaveId == 2) {
      return 5003;
    }
    return null;
  }

  static Map<int, List<TopologyPoint>> _groupPoints(List<TopologyPoint> points) {
    final grouped = <int, List<TopologyPoint>>{};
    for (final point in points) {
      grouped.putIfAbsent(point.moduleId, () => <TopologyPoint>[]).add(point);
    }
    return grouped;
  }

  static Map<int, List<TopologyCommand>> _groupCommands(
    List<TopologyCommand> commands,
  ) {
    final grouped = <int, List<TopologyCommand>>{};
    for (final command in commands) {
      grouped.putIfAbsent(command.moduleId, () => <TopologyCommand>[]).add(command);
    }
    return grouped;
  }
}
