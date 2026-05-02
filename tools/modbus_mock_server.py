#!/usr/bin/env python3
import argparse
import asyncio
import struct
import time

GH_MB_POINT_MAX = 180
GH_MB_POINT_STRIDE = 6
GH_MB_MAP_VERSION = 4
GH_MB_POINTS_BASE = 0
GH_MB_POINTS_REGS = GH_MB_POINT_MAX * GH_MB_POINT_STRIDE
GH_MB_SLAVE_STATUS_BLOCK_SIZE = 8
GH_MB_MAX_SLAVES = 20
GH_MB_SLAVE_STATUS_BASE = GH_MB_POINTS_BASE + GH_MB_POINTS_REGS
GH_MB_SLAVE_STATUS_REGS = GH_MB_MAX_SLAVES * GH_MB_SLAVE_STATUS_BLOCK_SIZE
GH_MB_CMD_PAYLOAD_WORDS = 16
GH_MB_CMD_BLOCK_SIZE = 4 + GH_MB_CMD_PAYLOAD_WORDS + 4
GH_MB_CMD_BASE = GH_MB_SLAVE_STATUS_BASE + GH_MB_SLAVE_STATUS_REGS
GH_MB_DIR_BASE = GH_MB_CMD_BASE + GH_MB_CMD_BLOCK_SIZE
GH_MB_CFG_BASE = GH_MB_DIR_BASE + 32
GH_MB_DIAG_BASE = GH_MB_CFG_BASE + 80
GH_MB_TOPO_BASE = GH_MB_DIAG_BASE + 32
GH_MB_TOPO_REGS = 144
GH_MB_TOTAL_REGS = GH_MB_TOPO_BASE + GH_MB_TOPO_REGS


def _u16(value: int) -> int:
    return value & 0xFFFF


def _u32_hi(value: int) -> int:
    return (value >> 16) & 0xFFFF


def _u32_lo(value: int) -> int:
    return value & 0xFFFF


class MockModbusMap:
    def __init__(self, generation: int, schema_major: int, schema_minor: int):
        self.regs = [0] * GH_MB_TOTAL_REGS
        self.generation = generation
        self.schema_major = schema_major
        self.schema_minor = schema_minor
        self.last_tick = int(time.time())
        self._init_map()

    def _init_map(self) -> None:
        # Directory (DIR)
        d = GH_MB_DIR_BASE
        self.regs[d + 0] = GH_MB_MAP_VERSION
        self.regs[d + 1] = 0x0003  # dir valid + topology active
        self.regs[d + 2] = _u32_hi(self.generation)
        self.regs[d + 3] = _u32_lo(self.generation)
        self.regs[d + 4] = GH_MB_POINT_MAX
        self.regs[d + 5] = GH_MB_POINT_STRIDE
        self.regs[d + 6] = GH_MB_POINTS_BASE
        self.regs[d + 7] = GH_MB_SLAVE_STATUS_BASE
        self.regs[d + 8] = GH_MB_CMD_BASE
        self.regs[d + 11] = GH_MB_POINT_MAX
        self.regs[d + 12] = GH_MB_CMD_BLOCK_SIZE
        self.regs[d + 13] = GH_MB_SLAVE_STATUS_BLOCK_SIZE
        self.regs[d + 14] = 12  # rtc hour
        self.regs[d + 15] = 0   # rtc minute
        self.regs[d + 20] = 0   # rtc set result idle

        # Topology metadata (TOPO)
        t = GH_MB_TOPO_BASE
        self.regs[t + 0] = 0   # submit token
        self.regs[t + 1] = 2   # result code applied
        self.regs[t + 2] = 0   # result token
        self.regs[t + 3] = 0x0001  # active
        self.regs[t + 4] = self.schema_major
        self.regs[t + 5] = self.schema_minor
        self.regs[t + 6] = _u32_hi(self.generation)
        self.regs[t + 7] = _u32_lo(self.generation)
        self.regs[t + 8] = 0
        self.regs[t + 9] = 4096  # active size bytes
        self.regs[t + 11] = 120   # req chunk words

        # Command block
        c = GH_MB_CMD_BASE
        self.regs[c + 22] = 0  # result idle
        self.regs[c + 23] = 0  # io err none

        # Slave status: mark first 2 slaves online
        for slave_idx in range(2):
            base = GH_MB_SLAVE_STATUS_BASE + slave_idx * GH_MB_SLAVE_STATUS_BLOCK_SIZE
            self.regs[base + 0] = 0x0001
            self.regs[base + 1] = 0

        # Points: set valid rows with dummy values/module ids
        for i in range(GH_MB_POINT_MAX):
            p = GH_MB_POINTS_BASE + i * GH_MB_POINT_STRIDE
            value = float(i) * 0.1
            raw = struct.unpack(">I", struct.pack(">f", value))[0]
            self.regs[p + 0] = _u32_hi(raw)
            self.regs[p + 1] = _u32_lo(raw)
            self.regs[p + 2] = 0  # quality ok
            self.regs[p + 3] = 0  # age
            self.regs[p + 4] = 100 + (i % 4)  # module id
            self.regs[p + 5] = 0x0001  # valid

    def tick(self) -> None:
        now = int(time.time())
        if now == self.last_tick:
            return
        elapsed = now - self.last_tick
        self.last_tick = now
        # age counters
        for i in range(GH_MB_POINT_MAX):
            p = GH_MB_POINTS_BASE + i * GH_MB_POINT_STRIDE
            self.regs[p + 3] = _u16(self.regs[p + 3] + elapsed)
        for slave_idx in range(2):
            base = GH_MB_SLAVE_STATUS_BASE + slave_idx * GH_MB_SLAVE_STATUS_BLOCK_SIZE
            self.regs[base + 1] = _u16(self.regs[base + 1] + elapsed)

    def read(self, start: int, qty: int) -> list[int] | None:
        if start < 0 or qty <= 0 or start + qty > GH_MB_TOTAL_REGS:
            return None
        return self.regs[start:start + qty]

    def write_single(self, addr: int, value: int) -> bool:
        return self.write_multi(addr, [value])

    def write_multi(self, start: int, values: list[int]) -> bool:
        qty = len(values)
        if start < 0 or qty <= 0 or start + qty > GH_MB_TOTAL_REGS:
            return False
        for i, v in enumerate(values):
            self.regs[start + i] = _u16(v)
        self._apply_side_effects(start, qty)
        return True

    def _apply_side_effects(self, start: int, qty: int) -> None:
        # RTC set: DIR offsets 16,17,18 -> applied token/result/hour/minute
        d = GH_MB_DIR_BASE
        rtc_token_addr = d + 18
        if start <= rtc_token_addr < (start + qty):
            hour = self.regs[d + 16]
            minute = self.regs[d + 17]
            token = self.regs[d + 18]
            self.regs[d + 19] = token
            if hour <= 23 and minute <= 59:
                self.regs[d + 14] = hour
                self.regs[d + 15] = minute
                self.regs[d + 20] = 2  # applied
            else:
                self.regs[d + 20] = 3  # reject range

        # Command trigger: mark as applied immediately
        c = GH_MB_CMD_BASE
        cmd_trigger_addr = c + 20
        if start <= cmd_trigger_addr < (start + qty):
            trig = self.regs[c + 20]
            if trig != 0:
                self.regs[c + 21] = trig  # last applied trigger
                self.regs[c + 22] = 2     # applied
                self.regs[c + 23] = 0     # io err none

        # Topology submit token: mark queued->applied
        t = GH_MB_TOPO_BASE
        topo_submit_addr = t + 0
        if start <= topo_submit_addr < (start + qty):
            token = self.regs[t + 0]
            if token != 0:
                self.regs[t + 2] = token
                self.regs[t + 1] = 2  # applied


def _normalize_addr(addr: int) -> int:
    # Mirror firmware behavior: accept raw or 41000-style addressing.
    if addr >= 41000:
        return addr - 41000
    return addr


def _exc(fc: int, code: int) -> bytes:
    return bytes([(fc | 0x80) & 0xFF, code & 0xFF])


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, mbmap: MockModbusMap) -> None:
    try:
        while True:
            header = await reader.readexactly(7)
            tx_id, proto_id, length = struct.unpack(">HHH", header[:6])
            unit_id = header[6]
            if proto_id != 0 or length < 2:
                break
            pdu = await reader.readexactly(length - 1)
            fc = pdu[0]
            resp_pdu: bytes

            if fc == 0x03 and len(pdu) == 5:
                start, qty = struct.unpack(">HH", pdu[1:5])
                start = _normalize_addr(start)
                mbmap.tick()
                data = mbmap.read(start, qty)
                if data is None or qty > 125:
                    resp_pdu = _exc(fc, 0x02)
                else:
                    payload = b"".join(struct.pack(">H", v) for v in data)
                    resp_pdu = bytes([0x03, len(payload)]) + payload
            elif fc == 0x06 and len(pdu) == 5:
                addr, value = struct.unpack(">HH", pdu[1:5])
                addr = _normalize_addr(addr)
                ok = mbmap.write_single(addr, value)
                resp_pdu = pdu if ok else _exc(fc, 0x02)
            elif fc == 0x10 and len(pdu) >= 6:
                start, qty, byte_count = struct.unpack(">HHB", pdu[1:6])
                start = _normalize_addr(start)
                if qty == 0 or qty > 123 or byte_count != qty * 2 or len(pdu) != 6 + byte_count:
                    resp_pdu = _exc(fc, 0x03)
                else:
                    vals = [
                        struct.unpack(">H", pdu[6 + i * 2:8 + i * 2])[0]
                        for i in range(qty)
                    ]
                    ok = mbmap.write_multi(start, vals)
                    resp_pdu = pdu[:5] if ok else _exc(fc, 0x02)
            else:
                resp_pdu = _exc(fc, 0x01)

            mbap = struct.pack(">HHHB", tx_id, 0, len(resp_pdu) + 1, unit_id)
            writer.write(mbap + resp_pdu)
            await writer.drain()
    except (asyncio.IncompleteReadError, ConnectionResetError):
        pass
    finally:
        writer.close()
        await writer.wait_closed()


async def main_async(host: str, port: int, generation: int, schema_major: int, schema_minor: int) -> None:
    mbmap = MockModbusMap(generation=generation, schema_major=schema_major, schema_minor=schema_minor)
    server = await asyncio.start_server(
        lambda r, w: handle_client(r, w, mbmap),
        host,
        port,
    )
    addrs = ", ".join(str(sock.getsockname()) for sock in server.sockets or [])
    print(f"Mock Modbus TCP server listening on {addrs}")
    print(f"Map: version={GH_MB_MAP_VERSION} points={GH_MB_POINT_MAX} cmd_base={GH_MB_CMD_BASE} dir_base={GH_MB_DIR_BASE} topo_base={GH_MB_TOPO_BASE}")
    async with server:
        await server.serve_forever()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Greenhouse local mock Modbus TCP device")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=1502)
    parser.add_argument("--generation", type=int, default=1)
    parser.add_argument("--schema-major", type=int, default=2)
    parser.add_argument("--schema-minor", type=int, default=0)
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    try:
        asyncio.run(
            main_async(
                host=args.host,
                port=args.port,
                generation=args.generation,
                schema_major=args.schema_major,
                schema_minor=args.schema_minor,
            ),
        )
    except KeyboardInterrupt:
        pass
