# Host Runtime (PC as Device)

This runtime lets your machine act as the greenhouse control device, so Flutter can run without STM32.

## Run

```bash
python tools/host_runtime/run_host_runtime.py --host 127.0.0.1 --port 1502 --generation 107 --schema-major 2 --schema-minor 0
```

Then run Flutter in emulated profile.

## What it does now

- Hosts Modbus TCP (FC3/FC6/FC16) with map layout expected by SCADA.
- Publishes core telemetry points (air temp/humidity, water rail, window positions).
- Accepts command trigger writes and applies a light command into adapter state.
- Uses a simulated device adapter by default.

## Next extension points

- Add adapter for real MCU transport (UART/TCP/MQTT).
- Map more command payload semantics from topology/command contracts.
- Persist runtime state/config in local DB.

## About `block_control2`

`D:\Workspace\ogurcy\block_control2` is an ESP-IDF firmware project for an ESP32-based field controller:

- Reads sensors (ADS1115 RH, MAX31865 PT500, DS3231 RTC)
- Controls actuators (RLL400 windows, 3-way valve, light relays)
- Exposes a Modbus **RTU slave** register map over RS485/UART2

So it is a **field node firmware**, not your SCADA master. In the target architecture, host runtime is master and block controllers are pluggable nodes.
