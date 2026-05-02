from __future__ import annotations

import asyncio
import math
import time
from dataclasses import dataclass, field
from typing import Protocol

from .contracts import LightCommand, TelemetrySnapshot


class DeviceAdapter(Protocol):
    async def read_telemetry(self) -> TelemetrySnapshot:
        ...

    async def apply_light(self, command: LightCommand) -> None:
        ...


@dataclass
class SimulatedDeviceAdapter:
    start_ts: float = time.time()
    _last_light: LightCommand = field(
        default_factory=lambda: LightCommand(False, False),
    )

    async def read_telemetry(self) -> TelemetrySnapshot:
        t = time.time() - self.start_ts
        air = 22.5 + math.sin(t / 18.0) * 1.8
        rh = 62.0 + math.cos(t / 22.0) * 5.0
        water = 24.0 + math.sin(t / 15.0) * 1.2
        light_boost = 4.0 if (self._last_light.relay1_on or self._last_light.relay2_on) else 0.0
        windows = 20.0 + math.sin(t / 30.0) * 10.0
        outside = 14.5 + math.sin(t / 40.0) * 3.0
        solar = 320.0 + math.sin(t / 25.0) * 180.0
        await asyncio.sleep(0)
        return TelemetrySnapshot(
            air_temp_c=air + light_boost * 0.1,
            air_humidity_pct=max(10.0, min(95.0, rh)),
            water_rail_c=water,
            water_grow_c=water - 0.6,
            water_undertray_c=water - 1.1,
            water_upper_heat_c=water + 2.2,
            windows_pos_a_pct=max(0.0, min(100.0, windows)),
            windows_pos_b_pct=max(0.0, min(100.0, windows * 0.9)),
            curtain_pos_pct=0.0,
            outside_temp_c=outside,
            outside_humidity_pct=72.0 + math.cos(t / 36.0) * 8.0,
            wind_speed_ms=2.5 + abs(math.sin(t / 12.0)) * 2.0,
            wind_direction_deg=(180.0 + math.sin(t / 45.0) * 70.0) % 360.0,
            rain_flag=0.0,
            solar_radiation_wm2=max(0.0, solar),
            barometric_pressure_hpa=1012.0 + math.cos(t / 90.0) * 4.0,
            dew_point_c=outside - 2.8,
            weather_status_bits=0.0,
        )

    async def apply_light(self, command: LightCommand) -> None:
        self._last_light = command
        await asyncio.sleep(0)
