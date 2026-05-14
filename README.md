# dalymon

Simple Daly BMS telemetry monitor for Linux.

`dalymon.py` polls a Daly BMS over BLE, writes JSON Lines output, and can optionally write selected fields to InfluxDB.

## Features

- BLE polling for Daly BMS telemetry
- JSONL output (`battery_data.jsonl`)
- Optional stdout output for live monitoring
- Optional InfluxDB writes (voltage/current/soc/temp)
- Retry/backoff logic for transient BLE failures
- Helper report script (`report.py`) for quick energy/load summaries

## Requirements

- Python 3.11+
- BLE support on host
- Python packages:
  - `bleak`
  - `aiobmsble`
  - `influxdb-client` (if InfluxDB enabled)

For plotting utilities used during analysis:

- `matplotlib` (optional)

## Configuration

Use `daly.conf.example` as template:

1. Copy to local config:
   - `cp daly.conf.example daly.conf`
2. Set battery MAC address(es)
3. Adjust poll interval
4. Configure InfluxDB token/url/org/bucket if enabled

Notes:

- `daly.conf` is intentionally git-ignored.
- Runtime data files are git-ignored.

## Run

File output (default from config):

- `python3 dalymon.py`

Force stdout only:

- `python3 dalymon.py -o stdout`

File + stdout:

- `python3 dalymon.py -o both`

Output mode options:

- `auto` (default): follow config `jsonl.enabled`
- `file`
- `stdout`
- `both`

## Data Format

Each JSONL line contains one telemetry sample with fields such as:

- `timestamp`
- `battery`
- `voltage`
- `current`
- `battery_level`
- `cycle_charge`
- `cycle_capacity`
- `delta_voltage`
- `cell_voltages`
- `temp_values`
- and additional Daly-provided fields

Timestamps are written as UTC ISO8601 with `Z` suffix.

## Quick Report

Generate a quick summary from current JSONL data:

- `python3 report.py`

Shows:

- total consumed Wh/Ah
- estimated stationary load
- detected high-load intervals

## Health Assessment

Run a preliminary health assessment with explicit data sufficiency warnings:

- `python3 health_assessment.py`

Includes:

- load-step resistance proxies (pack/cell)
- imbalance by SOC band
- high-SOC first-hit cell behavior
- thermal response proxy
- rest-window/self-discharge checks
- fault event counts

## Repository Notes

Included:

- source code
- example config
- Sming ESP32 telemetry plan

Excluded from git:

- local config (`daly.conf`)
- local data (`battery_data.jsonl`, `battery_data.csv`)
- generated plots
- virtual environment
