#!/bin/bash
# ============================================================
# Prezio Pi Recorder - First Boot Auto-Setup
#
# This script runs ONCE on the first boot of a freshly flashed
# Raspberry Pi. It moves the recorder files from /boot/firmware/
# to /home/pi/ and runs the full setup.
#
# DO NOT run manually - it is triggered by a systemd service
# that is placed on the boot partition by prepare_sd.ps1.
# ============================================================

LOG="/var/log/prezio-firstboot.log"
exec > >(tee -a "$LOG") 2>&1

echo "========================================"
echo "Prezio First Boot - $(date)"
echo "========================================"

BOOT_SRC="/boot/firmware/prezio_setup"
TARGET="/home/pi/prezio-v2/pi_recorder"

if [ ! -d "$BOOT_SRC" ]; then
    echo "ERROR: $BOOT_SRC not found. Aborting."
    exit 1
fi

# Wait for network manager to be ready
echo "[1/4] Waiting for system to be ready..."
sleep 10

# Copy files from boot partition to home directory
echo "[2/4] Copying recorder files..."
mkdir -p "$TARGET"
cp -r "$BOOT_SRC"/* "$TARGET/"
chown -R pi:pi /home/pi/prezio-v2

# Run the main setup script
echo "[3/4] Running setup..."
cd "$TARGET"
bash setup_pi.sh

# Clean up: remove files from boot partition and disable this service
echo "[4/4] Cleaning up..."
rm -rf "$BOOT_SRC"
systemctl disable prezio-firstboot.service
rm -f /etc/systemd/system/prezio-firstboot.service

echo "========================================"
echo "Prezio First Boot COMPLETE - $(date)"
echo "Pi is ready. Connect to WiFi 'Prezio-Recorder'."
echo "========================================"
