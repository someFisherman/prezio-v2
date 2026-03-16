# ============================================================
# Prezio Pi Recorder - SD Card Preparation Script
#
# Run this AFTER flashing Raspberry Pi OS Lite (64-bit) with
# Raspberry Pi Imager (with SSH + user "pi" configured).
#
# This script copies all necessary files onto the boot
# partition so the Pi sets itself up on first boot.
#
# Usage: Right-click -> "Run with PowerShell"
#    or: powershell -ExecutionPolicy Bypass -File prepare_sd.ps1
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Prezio Pi - SD-Karte vorbereiten" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Find boot partition (look for drives with "bootfs" label or config.txt)
$bootDrive = $null
$drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -lt 1GB -and $_.Free -gt 0 }
foreach ($d in $drives) {
    $configPath = Join-Path $d.Root "config.txt"
    if (Test-Path $configPath) {
        $bootDrive = $d.Root
        break
    }
}

if (-not $bootDrive) {
    Write-Host "Boot-Partition nicht automatisch gefunden." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Verfuegbare Laufwerke:"
    Get-PSDrive -PSProvider FileSystem | Format-Table Name, Root, @{N='Size (MB)';E={[math]::Round($_.Used/1MB)}} -AutoSize
    Write-Host ""
    $letter = Read-Host "Laufwerksbuchstabe der Boot-Partition eingeben (z.B. E)"
    $bootDrive = "${letter}:\"
}

if (-not (Test-Path (Join-Path $bootDrive "config.txt"))) {
    Write-Host "FEHLER: $bootDrive sieht nicht nach einer Pi Boot-Partition aus (config.txt fehlt)." -ForegroundColor Red
    Write-Host "Bitte zuerst mit Raspberry Pi Imager flashen!" -ForegroundColor Red
    Read-Host "Enter zum Beenden"
    exit 1
}

Write-Host "Boot-Partition gefunden: $bootDrive" -ForegroundColor Green
Write-Host ""

# Source directory (pi_recorder files)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceDir = $scriptDir

if (-not (Test-Path (Join-Path $sourceDir "pi_recorder.py"))) {
    Write-Host "FEHLER: pi_recorder.py nicht gefunden in $sourceDir" -ForegroundColor Red
    Read-Host "Enter zum Beenden"
    exit 1
}

# Copy recorder files to boot partition
$targetDir = Join-Path $bootDrive "prezio_setup"
Write-Host "[1/3] Kopiere Recorder-Dateien nach $targetDir ..."
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

$filesToCopy = @("pi_recorder.py", "setup_pi.sh", "requirements.txt", "firstboot.sh", "howto.txt")
foreach ($f in $filesToCopy) {
    $src = Join-Path $sourceDir $f
    if (Test-Path $src) {
        Copy-Item $src $targetDir -Force
        Write-Host "  + $f" -ForegroundColor Gray
    }
}

# Create the firstboot systemd service on the boot partition
Write-Host "[2/3] Erstelle First-Boot Service..."

$serviceContent = @"
[Unit]
Description=Prezio First Boot Auto-Setup
After=network-online.target NetworkManager.service
Wants=network-online.target
ConditionPathExists=/boot/firmware/prezio_setup

[Service]
Type=oneshot
ExecStart=/bin/bash /boot/firmware/prezio_setup/firstboot.sh
RemainAfterExit=no
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
"@

# Write service file to boot partition (will be installed via cmdline.txt hook)
$serviceContent | Set-Content (Join-Path $targetDir "prezio-firstboot.service") -Encoding UTF8

# Create an init script that installs the service on first boot
$initScript = @"
#!/bin/bash
# Move service file and enable it
cp /boot/firmware/prezio_setup/prezio-firstboot.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable prezio-firstboot.service
# Remove this init script from rc.local after first run
sed -i '/prezio_init/d' /etc/rc.local
"@

$initScript | Set-Content (Join-Path $targetDir "prezio_init.sh") -Encoding UTF8

# Modify rc.local to trigger the init on first boot
Write-Host "[3/3] Konfiguriere Auto-Start..."

$rcLocalPath = Join-Path $bootDrive "rc.local"
$rcLocalContent = @"
#!/bin/bash
# Prezio: install firstboot service if present
if [ -f /boot/firmware/prezio_setup/prezio_init.sh ]; then
    bash /boot/firmware/prezio_setup/prezio_init.sh
    rm -f /boot/firmware/prezio_setup/prezio_init.sh
    reboot
fi
exit 0
"@

# Note: rc.local is not on the boot partition in Bookworm.
# Instead, we use the firstrun mechanism via userconf.txt approach.
# For Bookworm, we create a simple cron job approach:

$cronScript = @"
#!/bin/bash
# This runs at boot via cron @reboot to install the firstboot service
if [ -f /boot/firmware/prezio_setup/prezio-firstboot.service ]; then
    cp /boot/firmware/prezio_setup/prezio-firstboot.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now prezio-firstboot.service
fi
"@

$cronScript | Set-Content (Join-Path $targetDir "install_service.sh") -Encoding UTF8

# Use the Raspberry Pi's firstrun.sh mechanism:
# After Pi Imager's own firstrun completes, we append our setup trigger
$firstrunPath = Join-Path $bootDrive "firstrun.sh"
$appendLine = "`n# Prezio auto-setup`nbash /boot/firmware/prezio_setup/firstboot.sh &`n"

if (Test-Path $firstrunPath) {
    # Append to existing firstrun.sh (created by Pi Imager)
    $content = Get-Content $firstrunPath -Raw
    # Insert before the final "exit 0" or at the end
    if ($content -match "exit 0") {
        $content = $content -replace "exit 0", "$appendLine`nexit 0"
    } else {
        $content += $appendLine
    }
    $content | Set-Content $firstrunPath -Encoding UTF8 -NoNewline
    Write-Host "  firstrun.sh erweitert (Prezio Setup wird beim ersten Boot ausgefuehrt)" -ForegroundColor Green
} else {
    # No firstrun.sh - create a custom one
    $newFirstrun = @"
#!/bin/bash
set +e
sleep 15
bash /boot/firmware/prezio_setup/firstboot.sh
exit 0
"@
    $newFirstrun | Set-Content $firstrunPath -Encoding UTF8
    Write-Host "  firstrun.sh erstellt" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " SD-Karte ist bereit!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Naechste Schritte:" -ForegroundColor Yellow
Write-Host "  1. SD-Karte sicher auswerfen"
Write-Host "  2. In den Pi Zero stecken"
Write-Host "  3. Strom anschliessen"
Write-Host "  4. 2-3 Minuten warten"
Write-Host "  5. WiFi 'Prezio-Recorder' verbinden (PW: prezio2026)"
Write-Host "  6. http://192.168.4.1:8080 testen"
Write-Host ""
Read-Host "Enter zum Beenden"
