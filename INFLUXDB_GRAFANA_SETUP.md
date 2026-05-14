# Battery Data Monitoring with InfluxDB and Grafana

This directory contains systemd user quadlets and scripts to run InfluxDB and Grafana for battery data monitoring.

## Files

- `quadlets/influxdb.container` - InfluxDB container quadlet
- `quadlets/grafana.container` - Grafana container quadlet
- `import_jsonl_to_influx.py` - Import script for battery data
- `setup_grafana.sh` - Grafana datasource configuration script
- `install_quadlets.sh` - Setup script to install everything

## Quick Start

1. **Install quadlets and dependencies:**
   ```bash
   bash install_quadlets.sh
   ```

2. **Start the services:**
   ```bash
   systemctl --user daemon-reload
   systemctl --user start influxdb grafana
   ```

3. **Wait for services to be ready** (30-60 seconds):
   ```bash
   systemctl --user status influxdb grafana
   ```

4. **Import your battery data:**
   ```bash
   python3 import_jsonl_to_influx.py battery_data.jsonl
   ```

5. **Configure Grafana datasource:**
   ```bash
   bash setup_grafana.sh
   ```

6. **Access Grafana:**
   - URL: http://localhost:3000
   - Username: `admin`
   - Password: `admin`

## Service Management

### Start services
```bash
systemctl --user start influxdb grafana
```

### Stop services
```bash
systemctl --user stop influxdb grafana
```

### Enable auto-start on login
```bash
systemctl --user enable influxdb grafana
```

### View logs
```bash
journalctl --user-unit influxdb -f
journalctl --user-unit grafana -f
```

### Restart a service
```bash
systemctl --user restart influxdb
systemctl --user restart grafana
```

## Data Import

The `import_jsonl_to_influx.py` script imports data from your JSONL file into InfluxDB:

```bash
# Import with default settings
python3 import_jsonl_to_influx.py battery_data.jsonl

# Custom InfluxDB credentials
python3 import_jsonl_to_influx.py battery_data.jsonl \
  --host localhost \
  --port 8086 \
  --username admin \
  --password adminpassword \
  --database battery_data

# Adjust batch size for large imports
python3 import_jsonl_to_influx.py battery_data.jsonl --batch-size 500
```

## Grafana Setup

The data is automatically organized as:
- **Measurement**: `battery_data`
- **Tag**: `battery` (battery name)
- **Fields**: voltage, current, temperature, power, cycles, etc.

Create dashboards in Grafana to visualize your battery data.

## Troubleshooting

### Services won't start
```bash
journalctl --user-unit influxdb -n 50
journalctl --user-unit grafana -n 50
```

### Import fails
- Ensure InfluxDB is running: `systemctl --user status influxdb`
- Check credentials in the script match your configuration
- Verify the JSONL file exists and is readable

### Can't access Grafana
- Ensure Grafana is running: `systemctl --user status grafana`
- Check that port 3000 is not in use: `lsof -i :3000`
- Check Grafana logs: `journalctl --user-unit grafana -f`

## Storage Locations

- **InfluxDB data**: `~/.local/share/influxdb/`
- **Grafana data**: `~/.local/share/grafana/`
- **Quadlets**: `~/.config/containers/systemd/`

To backup: `tar czf backup.tar.gz ~/.local/share/influxdb ~/.local/share/grafana`
