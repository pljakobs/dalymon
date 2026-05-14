#!/bin/bash
# Installer for the Daly BMS monitor service
# Installs Python files, creates a config, and sets up a systemd system service.
# Requires sudo for writing to /etc/ and /etc/systemd/system/.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_USER="${SUDO_USER:-$(id -un)}"
RUN_HOME=$(eval echo "~$RUN_USER")
INSTALL_DIR="${DALYMON_INSTALL_DIR:-$RUN_HOME/.local/lib/dalymon}"
CONFIG_FILE="/etc/dalymon.conf"
SERVICE_FILE="/etc/systemd/system/dalymon.service"
VENV_DIR="$INSTALL_DIR/.venv"
PYTHON="python3"

# ── helpers ───────────────────────────────────────────────────────────────────

bold()  { printf '\033[1m%s\033[0m' "$*"; }
info()  { echo "  $(bold '→') $*"; }
ok()    { echo "  ✓ $*"; }
warn()  { echo "  ⚠ $*"; }
die()   { echo "ERROR: $*" >&2; exit 1; }

ask() {
    local var="$1" prompt="$2" default="$3"
    local display_default=""
    [[ -n "$default" ]] && display_default=" [$default]"
    while true; do
        read -rp "  ${prompt}${display_default}: " value
        value="${value:-$default}"
        [[ -n "$value" ]] && break
        echo "    This field is required." >&2
    done
    printf -v "$var" '%s' "$value"
}

ask_bt_address() {
    local var="$1" prompt="$2" value
    while true; do
        read -rp "  ${prompt}: " value
        if [[ "$value" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
            break
        fi
        echo "    Please enter a valid Bluetooth MAC address (e.g. AA:BB:CC:DD:EE:FF)." >&2
    done
    printf -v "$var" '%s' "$value"
}

# Read a quoted string value for a key from a TOML file.
toml_get() {
    local key="$1" file="$2"
    grep -E "^${key}\s*=" "$file" 2>/dev/null \
        | sed -E 's/^[^=]+=\s*"([^"]*)"\s*$/\1/' \
        | head -1
}

# Update (in-place) a quoted string value for a key in a TOML file.
toml_set() {
    local key="$1" value="$2" file="$3"
    local escaped="${value//|/\\|}"
    sed -i "s|^${key}\s*=.*|${key} = \"${escaped}\"|" "$file"
}

# ── header ────────────────────────────────────────────────────────────────────

echo ""
echo "$(bold 'Daly BMS Monitor – Installer')"
echo "────────────────────────────────────────"
echo ""

# ── require root early ────────────────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
    die "This installer writes to /etc/ and requires root. Please re-run with: sudo bash $0"
fi

# ── read existing config (if present) ────────────────────────────────────────

CONFIG_EXISTS=false
UPDATE_INFLUX=false

INFLUX_URL="http://localhost:8086"
INFLUX_ORG="boat_systems"
INFLUX_BUCKET="power_telemetry"
INFLUX_TOKEN=""
BATTERY_NAME="Hausbatterie"
BATTERY_ADDR=""

if [[ -f "$CONFIG_FILE" ]]; then
    CONFIG_EXISTS=true

    existing_url=$(toml_get "url"    "$CONFIG_FILE")
    existing_org=$(toml_get "org"    "$CONFIG_FILE")
    existing_bucket=$(toml_get "bucket" "$CONFIG_FILE")
    existing_token=$(toml_get "token" "$CONFIG_FILE")

    if [[ -n "$existing_url" || -n "$existing_token" ]]; then
        echo "$(bold 'Existing InfluxDB config found in') $CONFIG_FILE:"
        echo "  URL    : ${existing_url:-(not set)}"
        echo "  Org    : ${existing_org:-(not set)}"
        echo "  Bucket : ${existing_bucket:-(not set)}"
        echo "  Token  : ${existing_token:0:8}…"
        echo ""
        read -rp "  Update InfluxDB settings? [y/N] " yn_influx
        if [[ "${yn_influx:-N}" =~ ^[Yy] ]]; then
            UPDATE_INFLUX=true
            INFLUX_URL="$existing_url"
            INFLUX_ORG="$existing_org"
            INFLUX_BUCKET="$existing_bucket"
            INFLUX_TOKEN="$existing_token"
        fi
        echo ""
    fi
fi

# ── gather InfluxDB settings (new install or user chose to update) ────────────

if [[ "$CONFIG_EXISTS" == false || "$UPDATE_INFLUX" == true ]]; then
    echo "$(bold 'InfluxDB connection')"
    ask INFLUX_URL    "InfluxDB URL"    "$INFLUX_URL"
    ask INFLUX_ORG    "InfluxDB org"    "$INFLUX_ORG"
    ask INFLUX_BUCKET "InfluxDB bucket" "$INFLUX_BUCKET"
    ask INFLUX_TOKEN  "InfluxDB token"  "$INFLUX_TOKEN"
    echo ""
fi

# ── gather battery info (new install only) ────────────────────────────────────

if [[ "$CONFIG_EXISTS" == false ]]; then
    echo "$(bold 'Battery configuration')"
    echo "  (You can add more batteries by editing $CONFIG_FILE after install)"
    echo ""
    ask            BATTERY_NAME "Battery name"                   "$BATTERY_NAME"
    ask_bt_address BATTERY_ADDR "Bluetooth address (AA:BB:CC:DD:EE:FF)"
    echo ""
fi

# ── confirm ───────────────────────────────────────────────────────────────────

echo "$(bold 'Installation plan')"
echo "  Running as user   : $RUN_USER"
echo "  Install directory : $INSTALL_DIR"
echo "  Config file       : $CONFIG_FILE"
echo "  Systemd service   : $SERVICE_FILE"
if [[ "$CONFIG_EXISTS" == false || "$UPDATE_INFLUX" == true ]]; then
    echo "  InfluxDB URL      : $INFLUX_URL"
    echo "  InfluxDB org      : $INFLUX_ORG"
    echo "  InfluxDB bucket   : $INFLUX_BUCKET"
    echo "  InfluxDB token    : ${INFLUX_TOKEN:0:8}…  (truncated)"
fi
echo ""
read -rp "  Continue? [Y/n] " yn
case "${yn:-Y}" in
    [Yy]*) ;;
    *) echo "Aborted."; exit 0 ;;
esac
echo ""

# ── install Python files ──────────────────────────────────────────────────────

info "Creating install directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

PYTHON_FILES=(
    dalymon.py
    health_assessment.py
    import_jsonl_to_influx.py
    report.py
    scan.py
    reset_influx_password.py
)

for f in "${PYTHON_FILES[@]}"; do
    if [[ -f "$SCRIPT_DIR/$f" ]]; then
        [[ -f "$INSTALL_DIR/$f" ]] && warn "$f already installed – overwriting"
        install -m 644 "$SCRIPT_DIR/$f" "$INSTALL_DIR/"
        ok "Installed $f"
    else
        warn "Source file not found, skipping: $f"
    fi
done

# ── set up Python virtual environment ─────────────────────────────────────────

if [[ ! -d "$VENV_DIR" ]]; then
    info "Creating Python virtual environment in $VENV_DIR"
    "$PYTHON" -m venv "$VENV_DIR"
    ok "Virtual environment created"
else
    ok "Virtual environment already exists, skipping creation"
fi

info "Installing Python dependencies"
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet bleak aiobmsble influxdb-client
ok "Dependencies installed"

# ── write / update config ─────────────────────────────────────────────────────

if [[ "$CONFIG_EXISTS" == false ]]; then
    cat > "$CONFIG_FILE" <<TOML
# Daly BMS Monitor configuration
# Generated by install.sh on $(date -Iseconds)

[logging]
level = "INFO"
interval = 60  # seconds between polls

[jsonl]
enabled = true
file_path = "$INSTALL_DIR/battery_data.jsonl"

[influxdb]
enabled = true
url = "$INFLUX_URL"
token = "$INFLUX_TOKEN"
org = "$INFLUX_ORG"
bucket = "$INFLUX_BUCKET"

[[batteries]]
name = "$BATTERY_NAME"
address = "$BATTERY_ADDR"

# Add more batteries by repeating the [[batteries]] block:
# [[batteries]]
# name = "Starterbatterie"
# address = "11:22:33:44:55:66"
TOML
    chmod 600 "$CONFIG_FILE"
    ok "Config written to $CONFIG_FILE (mode 600)"

elif [[ "$UPDATE_INFLUX" == true ]]; then
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    ok "Backed up existing config to ${CONFIG_FILE}.bak"
    toml_set "url"    "$INFLUX_URL"    "$CONFIG_FILE"
    toml_set "token"  "$INFLUX_TOKEN"  "$CONFIG_FILE"
    toml_set "org"    "$INFLUX_ORG"    "$CONFIG_FILE"
    toml_set "bucket" "$INFLUX_BUCKET" "$CONFIG_FILE"
    ok "InfluxDB settings updated in $CONFIG_FILE"

else
    ok "Config unchanged: $CONFIG_FILE"
fi

# ── systemd system service ────────────────────────────────────────────────────

if [[ -f "$SERVICE_FILE" ]]; then
    warn "Service file already exists at $SERVICE_FILE – skipping (delete to reinstall)"
else
    cat > "$SERVICE_FILE" <<UNIT
[Unit]
Description=Daly BMS BLE monitoring daemon
After=network.target bluetooth.target
Wants=network.target bluetooth.target

[Service]
Type=simple
User=$RUN_USER
ExecStart=$VENV_DIR/bin/python $INSTALL_DIR/dalymon.py --config $CONFIG_FILE
Restart=on-failure
RestartSec=30
UMask=0077

[Install]
WantedBy=multi-user.target
UNIT
    ok "Systemd service installed at $SERVICE_FILE"
fi

# ── enable & start ────────────────────────────────────────────────────────────

echo ""
systemctl daemon-reload
echo ""
read -rp "  Enable and start the dalymon service now? [Y/n] " yn_start
case "${yn_start:-Y}" in
    [Yy]*)
        systemctl enable --now dalymon
        echo ""
        ok "Service enabled and started"
        echo ""
        echo "  Check status : systemctl status dalymon"
        echo "  Follow logs  : journalctl -u dalymon -f"
        ;;
    *)
        echo ""
        info "To start the service manually:"
        echo "    sudo systemctl enable --now dalymon"
        ;;
esac

echo ""
echo "$(bold '✓ Installation complete')"
echo ""
echo "  Config file  : $CONFIG_FILE"
echo "  Install dir  : $INSTALL_DIR"
echo "  Service      : systemctl status dalymon"
echo ""
