import '../models/topology_models.dart';
import 'modbus_tcp_client.dart';
import 'register_map.dart';

class RegisterMapRuntime {
  RegisterMapRuntime({
    required ModbusTcpClient client,
    required RegisterMap registerMap,
  }) : _client = client,
       _registerMap = registerMap;

  final ModbusTcpClient _client;
  final RegisterMap _registerMap;

  Future<RegisterBootstrapResult> bootstrap() async {
    try {
      final directoryRegs = await _client.readHoldingRegisters(
        unitId: _registerMap.unitId,
        startAddress: _registerMap.directoryBase,
        count: _registerMap.directoryReadCount,
      );
      final directory = _decodeDirectory(directoryRegs);
      final contractError = _validateDirectory(directory);
      final topologyRegs = await _client.readHoldingRegisters(
        unitId: _registerMap.unitId,
        startAddress: _registerMap.topologyBase,
        count: 10,
      );
      final topologyMetadata = _decodeTopologyMetadata(topologyRegs);
      return RegisterBootstrapResult(
        directory: directory,
        topologyMetadata: topologyMetadata,
        contractError: contractError,
        bootstrapError: null,
      );
    } catch (e) {
      return RegisterBootstrapResult(
        directory: null,
        topologyMetadata: null,
        contractError: null,
        bootstrapError: e.toString(),
      );
    }
  }

  RegisterDirectorySnapshot _decodeDirectory(List<int> regs) {
    if (regs.length < _registerMap.directoryReadCount) {
      throw StateError(
        'DIR read too short: ${regs.length}/${_registerMap.directoryReadCount}',
      );
    }
    return RegisterDirectorySnapshot(
      mapVersion: regs[_registerMap.mapVersionReg] & 0xFFFF,
      mapFlags: regs[_registerMap.mapFlagsReg] & 0xFFFF,
      pointCount: regs[_registerMap.pointCountReg] & 0xFFFF,
      pointStride: regs[_registerMap.pointStrideReg] & 0xFFFF,
      pointsBase: regs[_registerMap.pointsBaseReg] & 0xFFFF,
      slaveStatusBase: regs[_registerMap.slaveStatusBaseReg] & 0xFFFF,
      cmdBase: regs[_registerMap.cmdBaseReg] & 0xFFFF,
      maxPoints: regs[_registerMap.maxPointsReg] & 0xFFFF,
      cmdBlockSize: regs[_registerMap.cmdBlockSizeReg] & 0xFFFF,
      statusBlockSize: regs[_registerMap.statusBlockSizeReg] & 0xFFFF,
      rtcHour: regs[_registerMap.rtcHourOffset] & 0xFFFF,
      rtcMinute: regs[_registerMap.rtcMinuteOffset] & 0xFFFF,
    );
  }

  DeviceTopologyMetadata _decodeTopologyMetadata(List<int> regs) {
    if (regs.length < 10) {
      throw StateError('TOPO metadata read too short: ${regs.length}/10');
    }
    return DeviceTopologyMetadata(
      resultCode: regs[_registerMap.topologyResultCodeOffset] & 0xFFFF,
      resultToken: regs[_registerMap.topologyResultTokenOffset] & 0xFFFF,
      flags: regs[_registerMap.topologyActiveFlagsOffset] & 0xFFFF,
      versionMajor: regs[_registerMap.topologyVersionMajorOffset] & 0xFFFF,
      versionMinor: regs[_registerMap.topologyVersionMinorOffset] & 0xFFFF,
      activeGeneration: _joinU32(
        regs[_registerMap.topologyGenerationHiOffset],
        regs[_registerMap.topologyGenerationLoOffset],
      ),
      activeSizeBytes: _joinU32(
        regs[_registerMap.topologySizeHiOffset],
        regs[_registerMap.topologySizeLoOffset],
      ),
    );
  }

  String? _validateDirectory(RegisterDirectorySnapshot directory) {
    if (directory.mapVersion != _registerMap.expectedMapVersion) {
      return 'MAP_VERSION=${directory.mapVersion} '
          '(expected ${_registerMap.expectedMapVersion})';
    }
    if (!directory.dirValid) {
      return 'DIR invalid: MAP_FLAGS=0x${directory.mapFlags.toRadixString(16)}';
    }
    if (directory.pointStride != _registerMap.expectedPointStride) {
      return 'POINT_STRIDE=${directory.pointStride} '
          '(expected ${_registerMap.expectedPointStride})';
    }
    if (directory.pointsBase != _registerMap.pointsBase) {
      return 'POINTS_BASE=${directory.pointsBase} '
          '(expected ${_registerMap.pointsBase})';
    }
    if (directory.slaveStatusBase != _registerMap.slaveStatusBase) {
      return 'SLAVE_STATUS_BASE=${directory.slaveStatusBase} '
          '(expected ${_registerMap.slaveStatusBase})';
    }
    if (directory.cmdBase != _registerMap.cmdBase) {
      return 'CMD_BASE=${directory.cmdBase} '
          '(expected ${_registerMap.cmdBase})';
    }
    if (directory.cmdBlockSize != _registerMap.expectedCmdBlockSize) {
      return 'CMD_BLOCK_SIZE=${directory.cmdBlockSize} '
          '(expected ${_registerMap.expectedCmdBlockSize})';
    }
    if (directory.statusBlockSize != _registerMap.expectedStatusBlockSize) {
      return 'STATUS_BLOCK_SIZE=${directory.statusBlockSize} '
          '(expected ${_registerMap.expectedStatusBlockSize})';
    }
    if (directory.maxPoints != _registerMap.expectedMaxPoints) {
      return 'MAX_POINTS=${directory.maxPoints} '
          '(expected ${_registerMap.expectedMaxPoints})';
    }
    return null;
  }

  int _joinU32(int hi, int lo) => ((hi & 0xFFFF) << 16) | (lo & 0xFFFF);
}
