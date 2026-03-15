#!/bin/bash
# ============================================================
# Prezio Pi Recorder - Setup Script
#
# Configures the Raspberry Pi as a WiFi Access Point and
# installs the Prezio recorder as a systemd service.
#
# Usage: sudo bash setup_pi.sh
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSID="${1:-Prezio-Recorder}"
PASSPHRASE="${2:-prezio2026}"
PI_IP="192.168.4.1"

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

# ------ System packages ------
echo "[1/6] Installing system packages..."
apt-get update -qq
apt-get install -y -qq hostapd dnsmasq python3 python3-pip python3-venv

# ------ Python environment ------
echo "[2/6] Setting up Python environment..."
VENV_DIR="$SCRIPT_DIR/venv"
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/pip" install --quiet -r "$SCRIPT_DIR/requirements.txt"

# ------ WiFi Access Point ------
echo "[3/6] Configuring WiFi Access Point..."

systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true

cat > /etc/hostapd/hostapd.conf << EOF
interface=wlan0
driver=nl80211
ssid=$SSID
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$PASSPHRASE
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

if ! grep -q '^DAEMON_CONF="/etc/hostapd/hostapd.conf"' /etc/default/hostapd 2>/dev/null; then
    echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >> /etc/default/hostapd
fi

# ------ Static IP for wlan0 ------
echo "[4/6] Configuring static IP..."

if ! grep -q "interface wlan0" /etc/dhcpcd.conf 2>/dev/null; then
    cat >> /etc/dhcpcd.conf << EOF

# Prezio Pi Recorder - Static IP for AP
interface wlan0
    static ip_address=${PI_IP}/24
    nohook wpa_supplicant
EOF
fi

# ------ DHCP Server (dnsmasq) ------
echo "[5/6] Configuring DHCP server..."

cat > /etc/dnsmasq.d/prezio.conf << EOF
interface=wlan0
dhcp-range=192.168.4.10,192.168.4.50,255.255.255.0,24h
domain=local
address=/prezio.local/$PI_IP
EOF

# ------ Systemd Service ------
echo "[6/6] Installing systemd service..."

cat > /etc/systemd/system/prezio-recorder.service << EOF
[Unit]
Description=Prezio Pi Recorder
After=network.target hostapd.service
Wants=hostapd.service

[Service]
Type=simple
User=root
WorkingDirectory=$SCRIPT_DIR
ExecStart=$VENV_DIR/bin/python3 $SCRIPT_DIR/pi_recorder.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# ------ Enable services ------
systemctl unmask hostapd
systemctl enable hostapd
systemctl enable dnsmasq
systemctl daemon-reload
systemctl enable prezio-recorder

echo ""
echo "=============================="
echo "Setup complete!"
echo ""
echo "Reboot to activate everything:"
echo "  sudo reboot"
echo ""
echo "After reboot:"
echo "  - WiFi AP: $SSID (password: $PASSPHRASE)"
echo "  - HTTP API: http://$PI_IP:8080"
echo "  - Service logs: journalctl -u prezio-recorder -f"
echo "=============================="
