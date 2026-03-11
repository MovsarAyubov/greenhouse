import '../models/topology_models.dart';

class ScheduleCommandContract {
  const ScheduleCommandContract({
    required this.primaryStep,
    required this.applyStep,
  });

  final TopologyCommand primaryStep;
  final TopologyCommand applyStep;
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
    final commands = _commandsByModuleId[moduleId] ?? const <TopologyCommand>[];
    TopologyCommand? primary;
    TopologyCommand? apply;
    for (final command in commands) {
      if (command.cmdKind != 'schedule') {
        continue;
      }
      if (command.fc == 16 &&
          command.startReg == 110 &&
          command.maxRegCount == 12 &&
          command.payloadOffset == 0) {
        primary = command;
      } else if (command.fc == 6 &&
          command.startReg == 122 &&
          command.maxRegCount == 1 &&
          command.payloadOffset == 12) {
        apply = command;
      }
    }
    if (primary == null || apply == null) {
      return null;
    }
    return ScheduleCommandContract(primaryStep: primary, applyStep: apply);
  }

  bool hasScheduleContract(int moduleId) =>
      scheduleContractForModule(moduleId) != null;

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
