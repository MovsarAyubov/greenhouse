# Local Mock Device (No STM32 Required)

Use this when you want `greenhouse` SCADA to run on your PC/Linux machine without the physical board.

## 1) Start the mock Modbus server

From repo root:

```bash
python tools/modbus_mock_server.py --host 127.0.0.1 --port 1502
```

Optional: match your local topology generation/schema so compatibility can become `ready`:

```bash
python tools/modbus_mock_server.py --host 127.0.0.1 --port 1502 --generation 1 --schema-major 2 --schema-minor 0
```

## 2) Point Flutter SCADA to localhost

In SCADA config:

- `host`: `127.0.0.1`
- `port`: `1502`
- `unitId`: `1`
- `addressMode`: `zeroBased`

## 3) Compatibility state behavior

- If local topology files are not configured, state can still show `localTopologyMissing`.
- If device is unreachable, state shows `deviceUnreachable`.
- To reach `ready`, local topology must be present and match mock `generation/schema`.

## Notes

- The mock implements Modbus TCP FC3/FC6/FC16.
- Register map layout mirrors firmware map v4 (`points/slave_status/cmd/dir/topo` bases expected by Flutter SCADA).
- RTC set, command trigger apply, and topology submit token transitions are simulated.
