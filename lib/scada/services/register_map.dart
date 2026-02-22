class RegisterMap {
  const RegisterMap({
    this.mapBase = 41000,
    this.zoneBlockSize = 64,
    this.readCount = 64,
    this.unitId = 1,
    this.sensorStart = 0,
    this.sensorCount = 9,
    this.sensorValidMaskReg = 9,
    this.outStateMaskReg = 10,
    this.outCmdMaskReg = 11,
    this.slaveStatusReg = 12,
    this.lastOkAgeSecReg = 13,
    this.errTimeoutReg = 14,
    this.errCrcReg = 15,
    this.errExceptionReg = 16,
    this.dataVersionReg = 17,
    this.modeReg = 20,
    this.setTempReg = 21,
    this.setHumReg = 22,
    this.hystTempReg = 23,
    this.hystHumReg = 24,
    this.minOnSecReg = 25,
    this.minOffSecReg = 26,
    this.applyTriggerReg = 60,
    this.lastAppliedTriggerReg = 61,
  });

  final int mapBase;
  final int zoneBlockSize;
  final int readCount;
  final int unitId;
  final int sensorStart;
  final int sensorCount;
  final int sensorValidMaskReg;
  final int outStateMaskReg;
  final int outCmdMaskReg;
  final int slaveStatusReg;
  final int lastOkAgeSecReg;
  final int errTimeoutReg;
  final int errCrcReg;
  final int errExceptionReg;
  final int dataVersionReg;
  final int modeReg;
  final int setTempReg;
  final int setHumReg;
  final int hystTempReg;
  final int hystHumReg;
  final int minOnSecReg;
  final int minOffSecReg;
  final int applyTriggerReg;
  final int lastAppliedTriggerReg;

  int zoneBase(int zoneId) => mapBase + (zoneId - 1) * zoneBlockSize;
  int zoneAddr(int zoneId, int offset) => zoneBase(zoneId) + offset;
  int zoneReadStart(int zoneId) => zoneBase(zoneId);

  static const RegisterMap assumed = RegisterMap();
}
