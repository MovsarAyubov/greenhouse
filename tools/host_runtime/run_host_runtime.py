#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import struct
from datetime import datetime
from dataclasses import dataclass
from pathlib import Path
import sys

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from host_runtime.contracts import LightCommand, RuntimeState, TelemetrySnapshot
    from host_runtime.devices import DeviceAdapter, SimulatedDeviceAdapter
else:
    from .contracts import LightCommand, RuntimeState, TelemetrySnapshot
    from .devices import DeviceAdapter, SimulatedDeviceAdapter

# Map mirrors greenhouse SCADA expected layout.
POINT_MAX = 180
POINT_STRIDE = 6
POINTS_BASE = 0
POINTS_REGS = POINT_MAX * POINT_STRIDE
SLAVE_STATUS_BLOCK = 8
SLAVE_STATUS_BASE = POINTS_BASE + POINTS_REGS
CMD_BASE = SLAVE_STATUS_BASE + (20 * SLAVE_STATUS_BLOCK)
DIR_BASE = CMD_BASE + 24
TOPO_BASE = DIR_BASE + 32 + 80 + 32
TOTAL_REGS = TOPO_BASE + 144


def _u16(v: int) -> int:
    return v & 0xFFFF


def _f32_to_words(value: float) -> tuple[int, int]:
    raw = struct.unpack(">I", struct.pack(">f", float(value)))[0]
    return (raw >> 16) & 0xFFFF, raw & 0xFFFF


@dataclass
class HostRuntime:
    adapter: DeviceAdapter
    generation: int
    schema_major: int
    schema_minor: int

    def __post_init__(self) -> None:
        self.regs = [0] * TOTAL_REGS
        self.state = RuntimeState(
            telemetry=TelemetrySnapshot(),
            light=LightCommand(False, False),
        )
        self._lighting_payload: list[int] = [0] * 13
        self._last_handled_trigger = 0
        self._init_registers()

    def _init_registers(self) -> None:
        d = DIR_BASE
        self.regs[d + 0] = 4
        self.regs[d + 1] = 0x0003
        self.regs[d + 2] = (self.generation >> 16) & 0xFFFF
        self.regs[d + 3] = self.generation & 0xFFFF
        self.regs[d + 4] = POINT_MAX
        self.regs[d + 5] = POINT_STRIDE
        self.regs[d + 6] = POINTS_BASE
        self.regs[d + 7] = SLAVE_STATUS_BASE
        self.regs[d + 8] = CMD_BASE
        self.regs[d + 11] = POINT_MAX
        self.regs[d + 12] = 24
        self.regs[d + 13] = SLAVE_STATUS_BLOCK
        self.regs[d + 14] = 12
        self.regs[d + 15] = 0
        self.regs[d + 20] = 0

        t = TOPO_BASE
        self.regs[t + 1] = 2
        self.regs[t + 3] = 0x0001
        self.regs[t + 4] = self.schema_major
        self.regs[t + 5] = self.schema_minor
        self.regs[t + 6] = (self.generation >> 16) & 0xFFFF
        self.regs[t + 7] = self.generation & 0xFFFF
        self.regs[t + 9] = 4096
        self.regs[t + 11] = 120

    async def update_from_adapter(self) -> None:
        self._apply_lighting_schedule()
        self.state.telemetry = await self.adapter.read_telemetry()
        self._write_points()

    def _write_points(self) -> None:
        status_bits = (
            (1 if self.state.light.relay1_on else 0)
            | (2 if self.state.light.relay2_on else 0)
        )
        light_output = (
            100.0
            if self.state.light.relay1_on and self.state.light.relay2_on
            else 50.0
            if self.state.light.relay1_on or self.state.light.relay2_on
            else 0.0
        )
        current_dli = max(0.0, self.state.telemetry.solar_radiation_wm2) / 100.0
        points = {
            0: (101, self.state.telemetry.air_temp_c),
            1: (101, self.state.telemetry.air_humidity_pct),
            2: (101, self.state.telemetry.water_rail_c),
            3: (101, self.state.telemetry.water_grow_c),
            4: (101, self.state.telemetry.water_undertray_c),
            5: (101, self.state.telemetry.water_upper_heat_c),
            6: (101, self.state.telemetry.windows_pos_a_pct),
            7: (101, self.state.telemetry.windows_pos_b_pct),
            8: (101, self.state.telemetry.curtain_pos_pct),
            9: (201, self.state.telemetry.outside_temp_c),
            10: (201, self.state.telemetry.outside_humidity_pct),
            11: (201, self.state.telemetry.wind_speed_ms),
            12: (201, self.state.telemetry.wind_direction_deg),
            13: (201, self.state.telemetry.solar_radiation_wm2),
            14: (201, self.state.telemetry.barometric_pressure_hpa),
            15: (201, self.state.telemetry.rain_flag),
            16: (201, self.state.telemetry.dew_point_c),
            17: (201, self.state.telemetry.weather_status_bits),
            18: (101, current_dli),
            19: (101, light_output),
            20: (101, float(status_bits)),
            21: (101, 0.0),
        }
        for i in range(POINT_MAX):
            p = POINTS_BASE + i * POINT_STRIDE
            point = points.get(i)
            if point is not None:
                module_id, value = point
                hi, lo = _f32_to_words(value)
                self.regs[p + 0] = hi
                self.regs[p + 1] = lo
                self.regs[p + 2] = 0
                self.regs[p + 3] = 0
                self.regs[p + 4] = module_id
                self.regs[p + 5] = 1
            else:
                self.regs[p + 0] = 0
                self.regs[p + 1] = 0
                self.regs[p + 2] = 3
                self.regs[p + 3] = 0xFFFF
                self.regs[p + 4] = 0
                self.regs[p + 5] = 0
        self._write_slave_status(1, online=True)
        self._write_slave_status(20, online=True)

    def _write_slave_status(self, slave_id: int, *, online: bool) -> None:
        if slave_id <= 0 or slave_id > 20:
            return
        base = SLAVE_STATUS_BASE + (slave_id - 1) * SLAVE_STATUS_BLOCK
        self.regs[base + 0] = 1 if online else 0
        self.regs[base + 1] = 0
        self.regs[base + 2] = 0
        self.regs[base + 3] = 0
        self.regs[base + 4] = 0
        self.regs[base + 5] = 1
        self.regs[base + 6] = 0xFFFF
        self.regs[base + 7] = (
            (1 if self.state.light.relay1_on else 0)
            | (2 if self.state.light.relay2_on else 0)
        )

    async def apply_cmd_trigger(self) -> None:
        c = CMD_BASE
        trigger = self.regs[c + 20]
        if trigger == 0 or trigger == self._last_handled_trigger:
            return
        self._last_handled_trigger = trigger
        payload_len = self.regs[c + 3]
        payload = [self.regs[c + 4 + i] for i in range(min(payload_len, 16))]
        if payload_len >= 13:
            self._lighting_payload = payload[:13]
            self._apply_lighting_schedule()
        cmd = self.state.light
        await self.adapter.apply_light(cmd)
        self.state.light = cmd
        self.regs[c + 21] = trigger
        self.regs[c + 22] = 2
        self.regs[c + 23] = 0
        print(
            f"[host-runtime] lighting apply trigger={trigger} "
            f"relay1={int(cmd.relay1_on)} relay2={int(cmd.relay2_on)} "
            f"payload_len={payload_len}"
        )

    def _apply_lighting_schedule(self) -> None:
        p = self._lighting_payload
        if len(p) < 13:
            self.state.light = LightCommand(False, False)
            return

        relay1_enabled = p[0] != 0
        relay1_on = p[1]
        relay1_off = p[2]
        relay2_enabled = p[6] != 0
        relay2_on = p[7]
        relay2_off = p[8]
        now_hhmm = self._current_hhmm()

        r1 = relay1_enabled and self._is_in_window(now_hhmm, relay1_on, relay1_off)
        r2 = relay2_enabled and self._is_in_window(now_hhmm, relay2_on, relay2_off)
        self.state.light = LightCommand(relay1_on=r1, relay2_on=r2)

    def _current_hhmm(self) -> int:
        now = datetime.now()
        return now.hour * 100 + now.minute

    def _is_in_window(self, now_hhmm: int, on_hhmm: int, off_hhmm: int) -> bool:
        if not self._valid_hhmm(on_hhmm) or not self._valid_hhmm(off_hhmm):
            return False
        if on_hhmm == off_hhmm:
            return True
        now_min = (now_hhmm // 100) * 60 + (now_hhmm % 100)
        on_min = (on_hhmm // 100) * 60 + (on_hhmm % 100)
        off_min = (off_hhmm // 100) * 60 + (off_hhmm % 100)
        if on_min < off_min:
            return on_min <= now_min < off_min
        return now_min >= on_min or now_min < off_min

    def _valid_hhmm(self, hhmm: int) -> bool:
        hh = hhmm // 100
        mm = hhmm % 100
        return 0 <= hh <= 23 and 0 <= mm <= 59


def _exc(fc: int, code: int) -> bytes:
    return bytes([(fc | 0x80) & 0xFF, code & 0xFF])


def _norm_addr(addr: int) -> int:
    return addr - 41000 if addr >= 41000 else addr


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, rt: HostRuntime) -> None:
    try:
        while True:
            hdr = await reader.readexactly(7)
            tx, proto, length = struct.unpack(">HHH", hdr[:6])
            unit = hdr[6]
            if proto != 0 or length < 2:
                break
            pdu = await reader.readexactly(length - 1)
            fc = pdu[0]
            resp: bytes
            if fc == 0x03 and len(pdu) == 5:
                start, qty = struct.unpack(">HH", pdu[1:5])
                start = _norm_addr(start)
                if qty == 0 or qty > 125 or start < 0 or start + qty > TOTAL_REGS:
                    resp = _exc(fc, 0x02)
                else:
                    vals = rt.regs[start:start + qty]
                    payload = b"".join(struct.pack(">H", v) for v in vals)
                    resp = bytes([0x03, len(payload)]) + payload
            elif fc == 0x06 and len(pdu) == 5:
                addr, value = struct.unpack(">HH", pdu[1:5])
                addr = _norm_addr(addr)
                if addr < 0 or addr >= TOTAL_REGS:
                    resp = _exc(fc, 0x02)
                else:
                    rt.regs[addr] = _u16(value)
                    await rt.apply_cmd_trigger()
                    resp = pdu
            elif fc == 0x10 and len(pdu) >= 6:
                start, qty, bc = struct.unpack(">HHB", pdu[1:6])
                start = _norm_addr(start)
                if qty == 0 or qty > 123 or bc != qty * 2 or len(pdu) != 6 + bc or start < 0 or start + qty > TOTAL_REGS:
                    resp = _exc(fc, 0x03)
                else:
                    for i in range(qty):
                        rt.regs[start + i] = struct.unpack(">H", pdu[6 + i * 2:8 + i * 2])[0]
                    await rt.apply_cmd_trigger()
                    resp = pdu[:5]
            else:
                resp = _exc(fc, 0x01)

            mbap = struct.pack(">HHHB", tx, 0, len(resp) + 1, unit)
            writer.write(mbap + resp)
            await writer.drain()
    except (asyncio.IncompleteReadError, ConnectionResetError):
        pass
    finally:
        writer.close()
        await writer.wait_closed()


async def updater(rt: HostRuntime) -> None:
    while True:
        await rt.update_from_adapter()
        await asyncio.sleep(1.0)


async def run(args: argparse.Namespace) -> None:
    adapter: DeviceAdapter = SimulatedDeviceAdapter()
    rt = HostRuntime(
        adapter=adapter,
        generation=args.generation,
        schema_major=args.schema_major,
        schema_minor=args.schema_minor,
    )
    server = await asyncio.start_server(
        lambda r, w: handle_client(r, w, rt),
        args.host,
        args.port,
    )
    print(f"Host runtime listening on {args.host}:{args.port}")
    print("Mode: simulated device adapter")
    print(f"Generation/schema: {args.generation}/{args.schema_major}.{args.schema_minor}")
    update_task = asyncio.create_task(updater(rt))
    async with server:
        try:
            await server.serve_forever()
        finally:
            update_task.cancel()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Greenhouse host runtime (PC as device)")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=1502)
    parser.add_argument("--generation", type=int, default=107)
    parser.add_argument("--schema-major", type=int, default=2)
    parser.add_argument("--schema-minor", type=int, default=0)
    return parser.parse_args()


if __name__ == "__main__":
    asyncio.run(run(parse_args()))
