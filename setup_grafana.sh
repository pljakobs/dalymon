#!/bin/bash
# Setup Grafana datasource for InfluxDB
# This script configures Grafana to use InfluxDB as a datasource

set -e

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"
INFLUXDB_URL="${INFLUXDB_URL:-http://localhost:8086}"
INFLUXDB_USER="${INFLUXDB_USER:-admin}"
INFLUXDB_PASSWORD="${INFLUXDB_PASSWORD:-adminpassword}"
INFLUXDB_DB="${INFLUXDB_DB:-battery_data}"

echo "Setting up Grafana datasource..."
echo "Grafana URL: $GRAFANA_URL"
echo "InfluxDB URL: $INFLUXDB_URL"

# Wait for Grafana to be ready
echo "Waiting for Grafana to be ready..."
for i in {1..30}; do
    if curl -s -f "$GRAFANA_URL/api/health" > /dev/null 2>&1; then
        echo "Grafana is ready!"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 1
done

# Add InfluxDB datasource
echo "Adding InfluxDB datasource..."
curl -X POST "$GRAFANA_URL/api/datasources" \
    -H "Content-Type: application/json" \
    -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    -d @- <<EOF
{
  "name": "InfluxDB",
  "type": "influxdb",
  "access": "proxy",
  "url": "$INFLUXDB_URL",
  "database": "$INFLUXDB_DB",
  "user": "$INFLUXDB_USER",
  "secureJsonData": {
    "password": "$INFLUXDB_PASSWORD"
  },
  "isDefault": true
}
EOF

echo ""
echo "Setup complete!"
echo ""
echo "Access Grafana at: $GRAFANA_URL"
echo "Username: $GRAFANA_USER"
echo "Password: $GRAFANA_PASSWORD"
