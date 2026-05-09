# ESP32 Daly Telemetry Reader Plan (Sming)

## Goal
Build a resilient ESP32-based Daly BMS telemetry reader using Sming, with wireless uplink to the onboard network (no long signal wires), and data compatibility with the existing JSONL/Influx flow.

## Scope
- Platform: ESP32 using Sming framework
- Source: Daly BMS via BLE (same telemetry family currently used by `dalymon.py`)
- Output transport: MQTT first, optional HTTP POST fallback
- Payload format: JSON fields aligned with current `battery_data.jsonl`
- Reliability: survive repeated BLE disconnects and WiFi outages

Out of scope for first version:
- On-device web UI
- OTA fleet management
- MPPT polling (separate phase)

## Architecture
1. BLE Collector Task
- Scan and connect to known Daly device (MAC preferred)
- Exchange request/response frames for telemetry
- Parse to typed telemetry struct

2. Publisher Task
- Serialize telemetry struct to JSON
- Publish to MQTT topic (QoS 1 recommended)
- Optional mirror to HTTP endpoint

3. Reliability Layer
- BLE reconnect loop with exponential backoff
- WiFi reconnect loop with bounded backoff
- Outbox buffer (ring buffer) for unsent samples during outages

4. Timekeeping
- NTP sync on boot
- Monotonic fallback if wall-clock unavailable

## Data Contract (JSON)
Use the same keys currently logged by host monitor whenever possible:
- timestamp
- battery
- voltage
- current
- battery_level
- cycle_charge
- cycle_capacity
- cell_count
- temp_sensors
- cycles
- delta_voltage
- problem_code
- balancer
- chrg_mosfet
- dischrg_mosfet
- cell_voltages
- temp_values
- power
- battery_charging
- runtime
- temperature
- problem

Add transport metadata:
- source: "esp32_sming"
- device_id: unique node id
- seq: incrementing sample counter
- rssi_ble: optional if available

## Sming Project Layout (proposed)
- app/application.cpp (entrypoint, scheduler setup)
- include/config.h (WiFi/MQTT/BMS settings)
- include/telemetry_types.h (sample struct + enums)
- src/ble_daly_client.cpp (BLE discovery, connect, frame I/O)
- src/ble_daly_parser.cpp (frame decode to telemetry struct)
- src/publisher_mqtt.cpp (MQTT connect/publish/retry)
- src/storage_outbox.cpp (ring buffer for unsent JSON)
- src/time_sync.cpp (NTP + timestamp helper)

## Milestones

### M1: Skeleton + Connectivity
- Initialize Sming app on ESP32
- WiFi connect/reconnect
- MQTT connect/reconnect
- Publish heartbeat JSON every 30s

Acceptance:
- Heartbeats visible in broker for 24h without manual intervention

### M2: Daly BLE Session + Raw Frames
- Scan for Daly device
- Connect and read notifications/characteristics
- Implement command write path and frame integrity checks

Acceptance:
- Raw frame poll loop stable for at least 2h
- Automatic recovery from forced BLE disconnect

### M3: Telemetry Parsing + JSON Contract
- Decode fields into telemetry struct
- Emit JSON matching host field names
- Include metadata fields

Acceptance:
- Sample payloads can be appended directly to existing JSONL pipeline

### M4: Reliability Hardening
- Exponential backoff for BLE and MQTT
- Outbox ring buffer for offline periods
- Flush buffered samples after reconnect

Acceptance:
- Survive 10+ induced BLE failures and 10+ WiFi outages without reboot

### M5: Host Integration
- Subscribe on host and append to `battery_data.jsonl`-compatible stream
- Optional Influx write bridge

Acceptance:
- End-to-end telemetry continuity across outages

## Polling Strategy
Initial defaults:
- Normal poll interval: 10s
- Fast poll interval: 2s (optional burst mode)
- Burst trigger: abs(current) >= 80A
- Burst duration: 45s after trigger

Notes:
- BLE stability is higher priority than sample rate
- Prefer stable 10s over unstable 2s

## Resilience Policy
- BLE connect failure: retry with delays 10s, 20s, 40s, ... max 300s
- MQTT failure: retry with delays 5s, 10s, 20s, ... max 120s
- Keep last good telemetry in RAM for diagnostics
- Emit reason codes for failures (scan_timeout, service_missing, crc_fail, publish_fail)

## Security + Operations
- Store credentials in Sming config, not hardcoded in source
- Support broker auth (username/password)
- Optional TLS later; start with LAN-only MQTT
- Add watchdog-safe loops (no blocking waits)

## Test Plan
Functional tests:
- Device found/not found
- Poll success and field validity
- JSON schema check against expected keys

Fault injection:
- Power cycle BMS during run
- Disable router/AP for 2-5 minutes
- Move ESP32 out of BLE range then restore

Performance tests:
- Sustained run for 24h and 72h
- Memory usage and outbox growth under network loss

## Risks and Mitigations
1. BLE instability on ESP32
- Mitigation: conservative polling, reconnect backoff, strict session cleanup

2. Parser drift across Daly variants
- Mitigation: isolate parser module, keep fixture frames, versioned decoder

3. Clock drift or no NTP at boot
- Mitigation: include monotonic age and resync timestamp once NTP is available

## Deliverables
1. Sming ESP32 firmware project with build instructions
2. MQTT telemetry stream compatible with existing host analytics
3. Host-side ingestion snippet for JSONL append
4. Basic runbook (boot, logs, recovery checks)

## Phase 2 (after MPPT)
- Add EPever MPPT telemetry source (ESP32 RS-485 Modbus or second node)
- Merge BMS + MPPT streams on timestamp for full energy-balance analytics
