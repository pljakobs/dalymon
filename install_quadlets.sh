#!/bin/bash
# Setup script for InfluxDB and Grafana with systemd user quadlets

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUADLET_DIR="$HOME/.config/containers/systemd"
INFLUXDB_DATA_DIR="$HOME/.local/share/influxdb"
GRAFANA_DATA_DIR="$HOME/.local/share/grafana"

echo "Setting up InfluxDB and Grafana quadlets..."
echo ""

# Create directories
mkdir -p "$QUADLET_DIR"
mkdir -p "$INFLUXDB_DATA_DIR"
mkdir -p "$GRAFANA_DATA_DIR"

# Copy quadlets
echo "Installing quadlets..."
cp "$SCRIPT_DIR/quadlets/influxdb.container" "$QUADLET_DIR/"
cp "$SCRIPT_DIR/quadlets/grafana.container" "$QUADLET_DIR/"
echo "  ✓ influxdb.container"
echo "  ✓ grafana.container"

# Install Python dependencies
echo ""
echo "Installing Python dependencies..."
if command -v pip &> /dev/null; then
    pip install influxdb-client
    echo "  ✓ influxdb-client"
else
    echo "  ⚠ pip not found. Please install influxdb-client manually:"
    echo "    pip install influxdb-client"
fi

# Make scripts executable
chmod +x "$SCRIPT_DIR/import_jsonl_to_influx.py"
chmod +x "$SCRIPT_DIR/setup_grafana.sh"
echo ""
echo "✓ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Start the services with:"
echo "   systemctl --user daemon-reload"
echo "   systemctl --user enable influxdb grafana"
echo "   systemctl --user start influxdb grafana"
echo ""
echo "2. Verify services are running:"
echo "   systemctl --user status influxdb grafana"
echo ""
echo "3. Wait for InfluxDB and Grafana to start (30-60 seconds), then import data:"
echo "   python3 $SCRIPT_DIR/import_jsonl_to_influx.py $SCRIPT_DIR/battery_data.jsonl"
echo ""
echo "4. Setup Grafana datasource:"
echo "   bash $SCRIPT_DIR/setup_grafana.sh"
echo ""
echo "5. Access Grafana at http://localhost:3000"
echo "   Default credentials: admin / admin"
echo ""
echo "View logs with:"
echo "   journalctl --user-unit influxdb -f"
echo "   journalctl --user-unit grafana -f"
