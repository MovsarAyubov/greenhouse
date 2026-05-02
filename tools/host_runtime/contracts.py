from __future__ import annotations

from dataclasses import dataclass


@dataclass
class TelemetrySnapshot:
    air_temp_c: float = 0.0
    air_humidity_pct: float = 0.0
    water_rail_c: float = 0.0
    water_grow_c: float = 0.0
    water_undertray_c: float = 0.0
    water_upper_heat_c: float = 0.0
    windows_pos_a_pct: float = 0.0
    windows_pos_b_pct: float = 0.0
    curtain_pos_pct: float = 0.0
    outside_temp_c: float = 0.0
    outside_humidity_pct: float = 0.0
    wind_speed_ms: float = 0.0
    wind_direction_deg: float = 0.0
    rain_flag: float = 0.0
    solar_radiation_wm2: float = 0.0
    barometric_pressure_hpa: float = 0.0
    dew_point_c: float = 0.0
    weather_status_bits: float = 0.0


@dataclass
class LightCommand:
    relay1_on: bool
    relay2_on: bool


@dataclass
class RuntimeState:
    telemetry: TelemetrySnapshot
    light: LightCommand
