import '../models/lighting_schedule_models.dart';

class RegisterMap {
  const RegisterMap({
    this.unitId = 1,
    this.directoryBaseCandidates = const <int>[1440],
    this.directoryReadCount = 14,
    this.expectedMapVersion = 2,
    this.expectedPointStride = 6,
    this.mapVersionReg = 0,
    this.mapFlagsReg = 1,
    this.topologyGenerationHiReg = 2,
    this.topologyGenerationLoReg = 3,
    this.pointCountReg = 4,
    this.pointStrideReg = 5,
    this.pointsBaseReg = 6,
    this.pointValueHiReg = 0,
    this.pointValueLoReg = 1,
    this.pointQualityReg = 2,
    this.pointAgeSecReg = 3,
    this.pointModuleIdReg = 4,
    this.pointFlagsReg = 5,
    this.pointValidFlagMask = 0x0001,
    this.sensorCount = 9,
    this.weatherPointStartIndex = 0,
    this.weatherPointCount = 9,
    this.topologyBase = 1584,
    this.topologyActiveOffset = 3,
    this.topologyGenerationHiOffset = 6,
    this.topologyGenerationLoOffset = 7,
    this.expectedTopologyGeneration = 8,
    this.expectedTopologyActiveFlag = 1,
    this.directoryPointCountAddress = 1444,
    this.rtcHourAddress = 1454,
    this.rtcMinuteAddress = 1455,
    this.rtcSetHourAddress = 1456,
    this.rtcSetMinuteAddress = 1457,
    this.rtcSetTokenAddress = 1458,
    this.rtcSetAppliedTokenAddress = 1459,
    this.rtcSetResultAddress = 1460,
    this.expectedPointCount = 12,
    this.weatherExpectedModuleId = 201,
    this.weatherPublishStartIndex = 3,
    this.mapBase = 41000,
    this.zoneBlockSize = 64,
    this.outCmdMaskReg = 11,
    this.modeReg = 20,
    this.setTempReg = 21,
    this.setHumReg = 22,
    this.hystTempReg = 23,
    this.hystHumReg = 24,
    this.minOnSecReg = 25,
    this.minOffSecReg = 26,
    this.applyTriggerReg = 60,
    this.lastAppliedTriggerReg = 61,
    this.scheduleBase = 1728,
    this.scheduleBlockSize = 20,
    this.scheduleSlaveMin = 1,
    this.scheduleSlaveMax = 20,
    this.scheduleSlotsCount = 4,
    this.scheduleSlotStride = 3,
    this.scheduleApplyValueOffset = 12,
    this.scheduleExpectedVersionHiOffset = 13,
    this.scheduleExpectedVersionLoOffset = 14,
    this.scheduleCmdKindOffset = 15,
    this.scheduleApplyTriggerOffset = 16,
    this.scheduleLastAppliedTriggerOffset = 17,
    this.scheduleLastResultOffset = 18,
    this.scheduleLastIoErrOffset = 19,
    this.schedulePayloadRegisterCount = 16,
    this.scheduleStateRegisterCount = 4,
    this.scheduleCommitStateRegisterCount = 3,
    this.scheduleCmdKindValue = 1,
    this.scheduleAddressBase41000 = 41000,
    this.schedulePollingPeriodMs = 500,
    this.schedulePollingTimeoutMs = 25000,
  });

  final int unitId;

  // Directory contract (start at 1440 or 42440)
  final List<int> directoryBaseCandidates;
  final int directoryReadCount;
  final int expectedMapVersion;
  final int expectedPointStride;
  final int mapVersionReg;
  final int mapFlagsReg;
  final int topologyGenerationHiReg;
  final int topologyGenerationLoReg;
  final int pointCountReg;
  final int pointStrideReg;
  final int pointsBaseReg;

  // Point row contract (stride = 6)
  final int pointValueHiReg;
  final int pointValueLoReg;
  final int pointQualityReg;
  final int pointAgeSecReg;
  final int pointModuleIdReg;
  final int pointFlagsReg;
  final int pointValidFlagMask;

  // UI sensor count shown by current SCADA screen.
  final int sensorCount;
  final int weatherPointStartIndex;
  final int weatherPointCount;
  final int topologyBase;
  final int topologyActiveOffset;
  final int topologyGenerationHiOffset;
  final int topologyGenerationLoOffset;
  final int expectedTopologyGeneration;
  final int expectedTopologyActiveFlag;
  final int directoryPointCountAddress;
  final int rtcHourAddress;
  final int rtcMinuteAddress;
  final int rtcSetHourAddress;
  final int rtcSetMinuteAddress;
  final int rtcSetTokenAddress;
  final int rtcSetAppliedTokenAddress;
  final int rtcSetResultAddress;
  final int expectedPointCount;
  final int weatherExpectedModuleId;
  final int weatherPublishStartIndex;

  // Legacy write window (kept for command path).
  final int mapBase;
  final int zoneBlockSize;
  final int outCmdMaskReg;
  final int modeReg;
  final int setTempReg;
  final int setHumReg;
  final int hystTempReg;
  final int hystHumReg;
  final int minOnSecReg;
  final int minOffSecReg;
  final int applyTriggerReg;
  final int lastAppliedTriggerReg;
  final int scheduleBase;
  final int scheduleBlockSize;
  final int scheduleSlaveMin;
  final int scheduleSlaveMax;
  final int scheduleSlotsCount;
  final int scheduleSlotStride;
  final int scheduleApplyValueOffset;
  final int scheduleExpectedVersionHiOffset;
  final int scheduleExpectedVersionLoOffset;
  final int scheduleCmdKindOffset;
  final int scheduleApplyTriggerOffset;
  final int scheduleLastAppliedTriggerOffset;
  final int scheduleLastResultOffset;
  final int scheduleLastIoErrOffset;
  final int schedulePayloadRegisterCount;
  final int scheduleStateRegisterCount;
  final int scheduleCommitStateRegisterCount;
  final int scheduleCmdKindValue;
  final int scheduleAddressBase41000;
  final int schedulePollingPeriodMs;
  final int schedulePollingTimeoutMs;

  int zoneBase(int zoneId) => mapBase + (zoneId - 1) * zoneBlockSize;
  bool isValidScheduleSlaveId(int slaveId) =>
      slaveId >= scheduleSlaveMin && slaveId <= scheduleSlaveMax;

  int scheduleBlockBaseOffset(int slaveId) =>
      scheduleBase + (slaveId - 1) * scheduleBlockSize;

  int scheduleAddressForOffset({
    required int offset,
    required ScheduleAddressMode mode,
  }) {
    return mode == ScheduleAddressMode.zeroBased
        ? offset
        : scheduleAddressBase41000 + offset;
  }

  int scheduleRegisterAddress({
    required int slaveId,
    required int blockOffset,
    required ScheduleAddressMode mode,
  }) {
    final absoluteOffset = scheduleBlockBaseOffset(slaveId) + blockOffset;
    return scheduleAddressForOffset(offset: absoluteOffset, mode: mode);
  }

  static const RegisterMap assumed = RegisterMap();
}
