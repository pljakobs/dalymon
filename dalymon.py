import asyncio
import argparse
import tomllib
import json
import os
from datetime import datetime, timezone
from bleak import BleakScanner
from aiobmsble.bms.daly_bms import BMS
from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import ASYNCHRONOUS

MAX_RETRY_DELAY = 300       # cap backoff at 5 minutes
INIT_RETRY_DELAY = 10       # first retry wait in seconds
MAX_RETRIES_PER_CYCLE = 4   # prevent one battery from blocking the full cycle
SCAN_TIMEOUT = 10           # BLE scan timeout in seconds
UPDATE_TIMEOUT = 20         # BMS update timeout in seconds


def utc_now_iso_z() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

async def poll_bms(config, battery_conf, influx_client, jsonl_file, write_to_file, write_to_stdout):
    mac = battery_conf['address']
    name = battery_conf['name']
    retry_delay = INIT_RETRY_DELAY

    for attempt in range(1, MAX_RETRIES_PER_CYCLE + 1):
        try:
            device = await asyncio.wait_for(
                BleakScanner.find_device_by_address(mac, timeout=SCAN_TIMEOUT),
                timeout=SCAN_TIMEOUT + 2,
            )
            if not device:
                raise RuntimeError("Device not found during scan")

            async with BMS(ble_device=device) as bms:
                data = await asyncio.wait_for(bms.async_update(), timeout=UPDATE_TIMEOUT)
                timestamp = utc_now_iso_z()

                # --- InfluxDB Export ---
                if config['influxdb']['enabled']:
                    point = Point("battery_status") \
                        .tag("battery_name", name) \
                        .field("voltage", float(data.get('voltage', 0))) \
                        .field("current", float(data.get('current', 0))) \
                        .field("soc", float(data.get('battery_level', 0))) \
                        .field("temp", float(data.get('temperature', 0)))

                    write_api = influx_client.write_api(write_options=ASYNCHRONOUS)
                    write_api.write(bucket=config['influxdb']['bucket'],
                                    org=config['influxdb']['org'],
                                    record=point)

                # --- JSONL Export ---
                record = {
                    'timestamp': timestamp,
                    'battery': name,
                    **data,
                }
                json_line = json.dumps(record, ensure_ascii=True, default=str)

                if write_to_file and jsonl_file is not None:
                    jsonl_file.write(json_line + "\n")
                    jsonl_file.flush()

                if write_to_stdout:
                    print(json_line)

                print(f"[{name}] Polled successfully: {data}")
                return  # success — let the main loop handle next interval

        except Exception as e:
            if attempt >= MAX_RETRIES_PER_CYCLE:
                print(f"[{name}] Poll failed after {attempt} attempt(s): {e}")
                return

            print(f"[{name}] Connection failed ({attempt}/{MAX_RETRIES_PER_CYCLE}): {e} — retrying in {retry_delay}s")
            await asyncio.sleep(retry_delay)
            retry_delay = min(retry_delay * 2, MAX_RETRY_DELAY)


def parse_args():
    parser = argparse.ArgumentParser(description="Daly BMS monitoring daemon")
    parser.add_argument(
        "-o",
        "--output",
        choices=["auto", "file", "stdout", "both"],
        default="auto",
        help="JSONL output sink: auto (from config), file, stdout, or both",
    )
    return parser.parse_args()


async def main(args):
    with open("daly.conf", "rb") as f:
        config = tomllib.load(f)

    config_file_output = config.get('jsonl', {}).get('enabled', False)
    if args.output == 'auto':
        write_to_file = config_file_output
        write_to_stdout = False
    elif args.output == 'file':
        write_to_file = True
        write_to_stdout = False
    elif args.output == 'stdout':
        write_to_file = False
        write_to_stdout = True
    else:  # both
        write_to_file = True
        write_to_stdout = True

    # Setup JSONL
    jsonl_file = None
    if write_to_file:
        os.makedirs(os.path.dirname(config['jsonl']['file_path']) or '.', exist_ok=True)
        jsonl_file = open(config['jsonl']['file_path'], mode='a', encoding='utf-8')

    # Setup Influx
    influx_client = None
    if config['influxdb']['enabled']:
        influx_client = InfluxDBClient(url=config['influxdb']['url'], 
                                       token=config['influxdb']['token'], 
                                       org=config['influxdb']['org'])

    while True:
        # Create tasks for all batteries to poll in parallel
        tasks = [poll_bms(config, b, influx_client, jsonl_file, write_to_file, write_to_stdout)
                 for b in config['batteries']]
        await asyncio.gather(*tasks, return_exceptions=True)
        await asyncio.sleep(config['logging']['interval'])

if __name__ == "__main__":
    args = parse_args()
    asyncio.run(main(args))
