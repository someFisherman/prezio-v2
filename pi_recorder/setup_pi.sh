#!/bin/bash
# ============================================================
# Prezio Pi Recorder - Setup Script (Bookworm / NetworkManager)
#
# Configures the Raspberry Pi as a WiFi Access Point and
# installs the Prezio recorder as a systemd service.
#
# Compatible with: Raspberry Pi OS Bookworm (64-bit Lite)
# Uses: NetworkManager (nmcli) instead of hostapd/dhcpcd
# Works OFFLINE if pyserial wheel is present in script dir.
#
# Usage: sudo bash setup_pi.sh
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSID="${1:-Prezio-Recorder}"
PASSPHRASE="${2:-prezio2026}"
PI_IP="192.168.4.1"
PYTHON=""

echo "=============================="
echo "Prezio Pi Recorder Setup"
echo "=============================="
echo "SSID:       $SSID"
echo "Passphrase: $PASSPHRASE"
echo "IP:         $PI_IP"
echo "Script dir: $SCRIPT_DIR"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root (sudo bash setup_pi.sh)"
    exit 1
fi

# ------ System packages (online or skip) ------
echo "[1/5] Checking system packages..."
if apt-get update -qq 2>/dev/null; then
    apt-get install -y -qq python3 python3-pip python3-venv 2>/dev/null || true
    echo "  Packages installed (online)"
else
    echo "  No internet - using pre-installed packages"
fi

# ------ Python environment ------
echo "[2/5] Setting up Python environment..."
VENV_DIR="$SCRIPT_DIR/venv"
WHL=$(ls "$SCRIPT_DIR"/pyserial-*.whl 2>/dev/null | head -1)

if python3 -m venv "$VENV_DIR" 2>/dev/null; then
    PYTHON="$VENV_DIR/bin/python3"
    if [ -n "$WHL" ]; then
        "$VENV_DIR/bin/pip" install --quiet "$WHL"
        echo "  pyserial installed from local wheel (venv)"
    else
        "$VENV_DIR/bin/pip" install --quiet -r "$SCRIPT_DIR/requirements.txt" 2>/dev/null || true
        echo "  pyserial installed from pip (venv)"
    fi
else
    PYTHON="python3"
    echo "  venv not available, using system Python"
    if [ -n "$WHL" ]; then
        python3 -m pip install --break-system-packages "$WHL" 2>/dev/null \
            || pip3 install --break-system-packages "$WHL" 2>/dev/null \
            || pip3 install "$WHL" 2>/dev/null \
            || true
        echo "  pyserial installed from local wheel (system)"
    else
        python3 -m pip install --break-system-packages pyserial 2>/dev/null \
            || pip3 install pyserial 2>/dev/null \
            || true
    fi
fi

# ------ WiFi Access Point via NetworkManager ------
echo "[3/5] Configuring WiFi Access Point (NetworkManager)..."

nmcli connection delete prezio-ap 2>/dev/null || true

for conn in $(nmcli -t -f NAME,DEVICE connection show | grep ":wlan0" | cut -d: -f1); do
    echo "  Removing existing connection: $conn"
    nmcli connection delete "$conn" 2>/dev/null || true
done

nmcli connection add \
    type wifi \
    ifname wlan0 \
    con-name prezio-ap \
    autoconnect yes \
    ssid "$SSID" \
    wifi.mode ap \
    wifi.band bg \
    wifi.channel 7 \
    ipv4.method shared \
    ipv4.addresses "${PI_IP}/24" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$PASSPHRASE"

nmcli connection up prezio-ap
echo "  AP active: $SSID on $PI_IP"

# ------ Data directory ------
echo "[4/5] Creating data directory..."
mkdir -p "$SCRIPT_DIR/data"
chown -R pi:pi "$SCRIPT_DIR/data" 2>/dev/null || true

# ------ Systemd Service ------
echo "[5/5] Installing systemd service..."

EXEC_PYTHON="$PYTHON"
if [ -f "$VENV_DIR/bin/python3" ]; then
    EXEC_PYTHON="$VENV_DIR/bin/python3"
fi

cat > /etc/systemd/system/prezio-recorder.service << EOF
[Unit]
Description=Prezio Pi Recorder
After=network-online.target NetworkManager.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$SCRIPT_DIR
ExecStart=$EXEC_PYTHON $SCRIPT_DIR/pi_recorder.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable prezio-recorder
systemctl start prezio-recorder

sleep 2
if systemctl is-active --quiet prezio-recorder; then
    echo "  Service running OK"
else
    echo "  WARNING: Service may not have started. Check: journalctl -u prezio-recorder"
fi

echo ""
echo "=============================="
echo "Setup complete!"
echo ""
echo "WiFi AP is already active:"
echo "  SSID:     $SSID"
echo "  Password: $PASSPHRASE"
echo "  IP:       $PI_IP"
echo "  HTTP API: http://$PI_IP:8080"
echo ""
echo "Service logs: journalctl -u prezio-recorder -f"
echo ""
echo "To reconnect via SSH after reboot:"
echo "  1. Connect to WiFi '$SSID'"
echo "  2. ssh pi@$PI_IP"
echo "=============================="
