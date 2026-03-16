#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Prezio Pi Flash Tool - Flasht und konfiguriert SD-Karten fuer Pi Zero 2 W.
.DESCRIPTION
    All-in-one: Laedt Pi OS herunter, flasht SD-Karte, konfiguriert WiFi AP,
    installiert Prezio Recorder. SD in Pi stecken, Strom dran, fertig.
.NOTES
    Benoetigt: Administrator-Rechte, 7-Zip
    Ausfuehrung: Rechtsklick -> "Mit PowerShell als Administrator ausfuehren"
    Oder: powershell -ExecutionPolicy Bypass -File prezio_flash.ps1
#>

$ErrorActionPreference = "Stop"

# ============================================================
# Configuration
# ============================================================
$PI_OS_URL     = "https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2025-05-13/2025-05-13-raspios-bookworm-arm64-lite.img.xz"
$PI_OS_XZ      = "2025-05-13-raspios-bookworm-arm64-lite.img.xz"
$PI_OS_IMG     = "2025-05-13-raspios-bookworm-arm64-lite.img"
$PYSERIAL_URL  = "https://files.pythonhosted.org/packages/07/bc/587a445451b253b285629263eb51c2d8e9bcea4fc97826266d186f96f558/pyserial-3.5-py2.py3-none-any.whl"
$PYSERIAL_WHL  = "pyserial-3.5-py2.py3-none-any.whl"

$PI_USER       = "pi"
$PI_PASS       = "prezio2026"
$PI_HOSTNAME   = "prezio-recorder"
$WIFI_SSID     = "Prezio-Recorder"
$WIFI_PASS     = "prezio2026"

$SCRIPT_DIR    = Split-Path -Parent $MyInvocation.MyCommand.Path
$CACHE_DIR     = Join-Path $SCRIPT_DIR ".flash_cache"

# ============================================================
# C# helper for raw disk writing via Win32 API
# ============================================================
Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public class RawDiskWriter {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(
        string lpFileName, uint dwDesiredAccess, uint dwShareMode,
        IntPtr lpSecurityAttributes, uint dwCreationDisposition,
        uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool WriteFile(
        SafeFileHandle hFile, byte[] lpBuffer, int nNumberOfBytesToWrite,
        out int lpNumberOfBytesWritten, IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool DeviceIoControl(
        SafeFileHandle hDevice, uint dwIoControlCode,
        IntPtr lpInBuffer, uint nInBufferSize,
        IntPtr lpOutBuffer, uint nOutBufferSize,
        out uint lpBytesReturned, IntPtr lpOverlapped);

    const uint GENERIC_WRITE      = 0x40000000;
    const uint GENERIC_READ       = 0x80000000;
    const uint FILE_SHARE_RW      = 0x3;
    const uint OPEN_EXISTING      = 3;
    const uint FSCTL_LOCK_VOLUME  = 0x00090018;
    const uint FSCTL_DISMOUNT     = 0x00090020;

    public static long WriteImage(string diskPath, string imgPath) {
        using (var handle = CreateFile(diskPath, GENERIC_READ | GENERIC_WRITE,
                FILE_SHARE_RW, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero)) {
            if (handle.IsInvalid)
                throw new IOException("Disk konnte nicht geoeffnet werden: Win32 error " +
                    Marshal.GetLastWin32Error());

            uint unused;
            DeviceIoControl(handle, FSCTL_LOCK_VOLUME, IntPtr.Zero, 0,
                IntPtr.Zero, 0, out unused, IntPtr.Zero);
            DeviceIoControl(handle, FSCTL_DISMOUNT, IntPtr.Zero, 0,
                IntPtr.Zero, 0, out unused, IntPtr.Zero);

            using (var img = File.OpenRead(imgPath))
            using (var disk = new FileStream(handle, FileAccess.ReadWrite)) {
                byte[] buf = new byte[1024 * 1024];
                long total = 0;
                int read;
                while ((read = img.Read(buf, 0, buf.Length)) > 0) {
                    int aligned = read;
                    if (aligned % 512 != 0) {
                        aligned = ((aligned / 512) + 1) * 512;
                        Array.Clear(buf, read, aligned - read);
                    }
                    disk.Write(buf, 0, aligned);
                    total += read;
                }
                disk.Flush();
                return total;
            }
        }
    }
}
"@

# ============================================================
# Functions
# ============================================================
function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  +======================================+" -ForegroundColor Cyan
    Write-Host "  |   PREZIO Pi Flash Tool               |" -ForegroundColor Cyan
    Write-Host "  |   Pi Zero 2 W - All-in-One Setup     |" -ForegroundColor Cyan
    Write-Host "  +======================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  SD-Karte rein -> Script starten -> fertig." -ForegroundColor Gray
    Write-Host ""
}

function Find-7Zip {
    $paths = @(
        "${env:ProgramFiles}\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        "${env:ProgramW6432}\7-Zip\7z.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Write-LF {
    param([string]$Path, [string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $lfContent = $Content -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($Path, $lfContent, $utf8NoBom)
}

# ============================================================
# Main
# ============================================================
Show-Banner

# --- Check admin ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  FEHLER: Bitte als Administrator ausfuehren!" -ForegroundColor Red
    Write-Host "  Rechtsklick -> 'Als Administrator ausfuehren'" -ForegroundColor Yellow
    Read-Host "`n  Enter zum Beenden"
    exit 1
}

# --- Find 7-Zip ---
$7z = Find-7Zip
if (-not $7z) {
    Write-Host "  FEHLER: 7-Zip nicht gefunden!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Bitte installieren: https://www.7-zip.org/" -ForegroundColor Yellow
    Write-Host "  (Kostenlos, dauert 1 Minute)" -ForegroundColor Gray
    Read-Host "`n  Enter zum Beenden"
    exit 1
}
Write-Host "  [OK] 7-Zip: $7z" -ForegroundColor Green

# --- Verify pi_recorder.py exists ---
$recorderPy = Join-Path $SCRIPT_DIR "pi_recorder.py"
if (-not (Test-Path $recorderPy)) {
    Write-Host "  FEHLER: pi_recorder.py nicht gefunden in $SCRIPT_DIR" -ForegroundColor Red
    Read-Host "`n  Enter zum Beenden"
    exit 1
}
Write-Host "  [OK] pi_recorder.py vorhanden" -ForegroundColor Green

# ============================================================
# Step 1: Download Pi OS + pyserial wheel
# ============================================================
New-Item -ItemType Directory -Path $CACHE_DIR -Force | Out-Null
$xzPath  = Join-Path $CACHE_DIR $PI_OS_XZ
$imgPath = Join-Path $CACHE_DIR $PI_OS_IMG
$whlPath = Join-Path $CACHE_DIR $PYSERIAL_WHL

if (Test-Path $imgPath) {
    Write-Host "  [OK] Pi OS Image gecached" -ForegroundColor Green
} else {
    if (-not (Test-Path $xzPath)) {
        Write-Host ""
        Write-Host "  [1/6] Lade Raspberry Pi OS herunter (~430 MB)..." -ForegroundColor Yellow
        Write-Host "         Das dauert je nach Internet 2-10 Minuten." -ForegroundColor Gray
        Write-Host ""
        $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri $PI_OS_URL -OutFile $xzPath -UseBasicParsing
        } catch {
            Write-Host "  FEHLER beim Download: $_" -ForegroundColor Red
            if (Test-Path $xzPath) { Remove-Item $xzPath -Force }
            Read-Host "`n  Enter zum Beenden"
            exit 1
        }
        $ProgressPreference = 'Continue'
        $sizeMB = [math]::Round((Get-Item $xzPath).Length / 1MB)
        Write-Host "  Download fertig: ${sizeMB} MB" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Pi OS Download gecached" -ForegroundColor Green
    }

    Write-Host "  [2/6] Entpacke Image..." -ForegroundColor Yellow
    & $7z x $xzPath "-o$CACHE_DIR" -y 2>&1 | Out-Null

    $extractedImg = Get-ChildItem $CACHE_DIR -Filter "*.img" | Select-Object -First 1
    if ($extractedImg -and $extractedImg.Name -ne $PI_OS_IMG) {
        Rename-Item $extractedImg.FullName $imgPath -Force
    }
    if (-not (Test-Path $imgPath)) {
        Write-Host "  FEHLER: Image konnte nicht entpackt werden!" -ForegroundColor Red
        Read-Host "`n  Enter zum Beenden"
        exit 1
    }
    Remove-Item $xzPath -Force -ErrorAction SilentlyContinue
    Write-Host "  Image entpackt" -ForegroundColor Green
}

# Download pyserial wheel
if (-not (Test-Path $whlPath)) {
    Write-Host "  Lade pyserial herunter..." -ForegroundColor Gray
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $PYSERIAL_URL -OutFile $whlPath -UseBasicParsing
    } catch {
        Write-Host "  Warnung: pyserial konnte nicht geladen werden (nicht kritisch)" -ForegroundColor Yellow
    }
    $ProgressPreference = 'Continue'
}

# ============================================================
# Step 2: Select SD card
# ============================================================
Write-Host ""
Write-Host "  [3/6] SD-Karte auswaehlen" -ForegroundColor Yellow
Write-Host ""

$disks = @(Get-Disk | Where-Object {
    ($_.BusType -eq 'USB' -or $_.BusType -eq 'SD') -and $_.Size -gt 1GB -and $_.Size -lt 128GB
})

if ($disks.Count -eq 0) {
    $disks = @(Get-Disk | Where-Object {
        $_.Size -gt 1GB -and $_.Size -lt 64GB -and
        $_.BusType -notin @('NVMe','SATA','RAID','Fibre Channel','SAS')
    })
}

if ($disks.Count -eq 0) {
    Write-Host "  Keine SD-Karte gefunden!" -ForegroundColor Red
    Write-Host "  Bitte SD-Karte einstecken und neu starten." -ForegroundColor Yellow
    Read-Host "`n  Enter zum Beenden"
    exit 1
}

Write-Host "  Gefundene Wechseldatentraeger:" -ForegroundColor White
Write-Host ""
foreach ($d in $disks) {
    $sizeGB = [math]::Round($d.Size / 1GB, 1)
    Write-Host ("    Disk {0}:  {1,5} GB  |  {2}" -f $d.Number, $sizeGB, $d.FriendlyName) -ForegroundColor White
}
Write-Host ""
$diskInput = Read-Host "  Disk-Nummer eingeben"
$diskNum = [int]$diskInput

$selectedDisk = $disks | Where-Object { $_.Number -eq $diskNum }
if (-not $selectedDisk) {
    Write-Host "  Ungueltige Disk-Nummer!" -ForegroundColor Red
    Read-Host "`n  Enter zum Beenden"
    exit 1
}

$sizeGB = [math]::Round($selectedDisk.Size / 1GB, 1)
Write-Host ""
Write-Host "  !! WARNUNG !!" -ForegroundColor Red
Write-Host "  Disk $diskNum  ($sizeGB GB - $($selectedDisk.FriendlyName))" -ForegroundColor Red
Write-Host "  ALLE DATEN AUF DIESER KARTE WERDEN GELOESCHT!" -ForegroundColor Red
Write-Host ""
$confirm = Read-Host "  Tippe 'JA' zum Fortfahren"
if ($confirm -ne 'JA') {
    Write-Host "  Abgebrochen." -ForegroundColor Yellow
    exit 0
}

# ============================================================
# Step 3: Clean disk
# ============================================================
Write-Host ""
Write-Host "  [4/6] Bereite SD-Karte vor..." -ForegroundColor Yellow

$dpClean = @"
select disk $diskNum
clean
"@
$dpClean | diskpart 2>&1 | Out-Null
Start-Sleep -Seconds 2
Write-Host "  SD-Karte bereinigt" -ForegroundColor Green

# ============================================================
# Step 4: Flash image
# ============================================================
Write-Host "  [5/6] Schreibe Image auf SD-Karte..." -ForegroundColor Yellow
$imgSize = (Get-Item $imgPath).Length
$imgSizeMB = [math]::Round($imgSize / 1MB)
Write-Host "         Image: ${imgSizeMB} MB - das dauert ca. 2-5 Minuten" -ForegroundColor Gray

$physDrive = "\\.\PhysicalDrive$diskNum"
try {
    $written = [RawDiskWriter]::WriteImage($physDrive, $imgPath)
    $writtenMB = [math]::Round($written / 1MB)
    Write-Host "  ${writtenMB} MB geschrieben" -ForegroundColor Green
} catch {
    Write-Host "  FEHLER beim Schreiben: $_" -ForegroundColor Red
    Read-Host "`n  Enter zum Beenden"
    exit 1
}

# ============================================================
# Step 5: Configure boot partition
# ============================================================
Write-Host "  [6/6] Konfiguriere Boot-Partition..." -ForegroundColor Yellow

# Rescan disk so Windows sees new partitions
$dpRescan = "rescan"
$dpRescan | diskpart 2>&1 | Out-Null
Start-Sleep -Seconds 3

# Try to find and mount the boot partition
$bootLetter = $null
for ($attempt = 0; $attempt -lt 10; $attempt++) {
    try {
        $parts = Get-Partition -DiskNumber $diskNum -ErrorAction SilentlyContinue
        $bootPart = $parts | Where-Object { $_.Size -lt 1GB -and $_.Size -gt 100MB } | Select-Object -First 1
        if ($bootPart) {
            if (-not $bootPart.DriveLetter -or $bootPart.DriveLetter -eq [char]0) {
                $freeLetter = 67..90 | ForEach-Object { [char]$_ } |
                    Where-Object { -not (Test-Path "${_}:\") } | Select-Object -Last 1
                $bootPart | Set-Partition -NewDriveLetter $freeLetter -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
                $bootLetter = $freeLetter
            } else {
                $bootLetter = $bootPart.DriveLetter
            }
            if (Test-Path "${bootLetter}:\config.txt") { break }
        }
    } catch {}
    Start-Sleep -Seconds 2
}

if (-not $bootLetter -or -not (Test-Path "${bootLetter}:\config.txt")) {
    Write-Host "  FEHLER: Boot-Partition konnte nicht gefunden werden!" -ForegroundColor Red
    Write-Host "  Bitte SD-Karte manuell mit prepare_sd.ps1 konfigurieren." -ForegroundColor Yellow
    Read-Host "`n  Enter zum Beenden"
    exit 1
}

$bootRoot = "${bootLetter}:\"
Write-Host "  Boot-Partition: $bootRoot" -ForegroundColor Green

# --- Enable SSH ---
New-Item -ItemType File -Path (Join-Path $bootRoot "ssh") -Force | Out-Null

# --- Copy prezio files ---
$setupDir = Join-Path $bootRoot "prezio_setup"
New-Item -ItemType Directory -Path $setupDir -Force | Out-Null

$filesToCopy = @("pi_recorder.py", "setup_pi.sh", "requirements.txt", "howto.txt")
foreach ($f in $filesToCopy) {
    $src = Join-Path $SCRIPT_DIR $f
    if (Test-Path $src) { Copy-Item $src $setupDir -Force }
}
if (Test-Path $whlPath) {
    Copy-Item $whlPath $setupDir -Force
}

# --- Create firstrun.sh ---
$firstrunContent = @"
#!/bin/bash
set +e

LOG=/var/log/prezio-firstboot.log
exec > >(tee -a "`$LOG") 2>&1

echo "==== Prezio First Boot - `$(date) ===="

# Create user pi
FIRSTUSER=`$(getent passwd 1000 | cut -d: -f1)
if [ -z "`$FIRSTUSER" ]; then
    useradd -m -G sudo,adm,dialout,audio,video,plugdev,games,users,input,netdev,gpio,i2c,spi pi
fi
echo "pi:$PI_PASS" | chpasswd

# Hostname
echo "$PI_HOSTNAME" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\t$PI_HOSTNAME/" /etc/hosts

# SSH
systemctl enable ssh
systemctl start ssh

# Wait for system to settle
sleep 5

# Copy files from boot partition
SRC=/boot/firmware/prezio_setup
DST=/home/pi/prezio-v2/pi_recorder
mkdir -p `$DST
cp `$SRC/pi_recorder.py `$DST/
cp `$SRC/setup_pi.sh `$DST/
cp `$SRC/requirements.txt `$DST/
cp `$SRC/howto.txt `$DST/ 2>/dev/null
cp `$SRC/pyserial-*.whl `$DST/ 2>/dev/null
chown -R pi:pi /home/pi/prezio-v2

# Run setup (AP + service)
cd `$DST
bash setup_pi.sh

# Cleanup
rm -rf /boot/firmware/prezio_setup
rm -f /boot/firmware/firstrun.sh
sed -i 's| systemd.run.*||g' /boot/firmware/cmdline.txt

echo "==== Prezio First Boot COMPLETE ===="
exit 0
"@

Write-LF -Path (Join-Path $bootRoot "firstrun.sh") -Content $firstrunContent

# --- Modify cmdline.txt to trigger firstrun ---
$cmdlinePath = Join-Path $bootRoot "cmdline.txt"
if (Test-Path $cmdlinePath) {
    $cmdline = (Get-Content $cmdlinePath -Raw).Trim()
    if ($cmdline -notmatch "systemd.run=") {
        $cmdline += " systemd.run=/boot/firmware/firstrun.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target"
        Write-LF -Path $cmdlinePath -Content ($cmdline + "`n")
    }
}

Write-Host "  Konfiguration geschrieben" -ForegroundColor Green

# ============================================================
# Done
# ============================================================
Write-Host ""
Write-Host "  +======================================+" -ForegroundColor Green
Write-Host "  |   SD-KARTE FERTIG!                   |" -ForegroundColor Green
Write-Host "  +======================================+" -ForegroundColor Green
Write-Host ""
Write-Host "  Naechste Schritte:" -ForegroundColor Yellow
Write-Host "    1. SD-Karte sicher auswerfen" -ForegroundColor White
Write-Host "    2. In den Pi Zero 2 W stecken" -ForegroundColor White
Write-Host "    3. Strom anschliessen (USB)" -ForegroundColor White
Write-Host "    4. 3-5 Minuten warten" -ForegroundColor White
Write-Host "    5. WiFi '$WIFI_SSID' verbinden" -ForegroundColor White
Write-Host "       Passwort: $WIFI_PASS" -ForegroundColor Gray
Write-Host "    6. http://192.168.4.1:8080 testen" -ForegroundColor White
Write-Host ""
Write-Host "  SSH-Zugang:" -ForegroundColor Yellow
Write-Host "    ssh ${PI_USER}@192.168.4.1" -ForegroundColor White
Write-Host "    Passwort: $PI_PASS" -ForegroundColor Gray
Write-Host ""
Read-Host "  Enter zum Beenden"
