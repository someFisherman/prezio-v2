"""
PrezioImager - All-in-one SD-Karten Flash Tool fuer Pi Zero 2 W
Soleco AG
"""

import ctypes
import ctypes.wintypes
import io
import json
import lzma
import os
import struct
import subprocess
import sys
import threading
import tkinter as tk
from tkinter import ttk, messagebox
from pathlib import Path
from urllib.request import urlopen, Request

# ============================================================
# Config
# ============================================================
PI_OS_URL = "https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2025-05-13/2025-05-13-raspios-bookworm-arm64-lite.img.xz"
PI_OS_XZ = "2025-05-13-raspios-bookworm-arm64-lite.img.xz"
PI_OS_IMG = "2025-05-13-raspios-bookworm-arm64-lite.img"
PYSERIAL_URL = "https://files.pythonhosted.org/packages/07/bc/587a445451b253b285629263eb51c2d8e9bcea4fc97826266d186f96f558/pyserial-3.5-py2.py3-none-any.whl"
PYSERIAL_WHL = "pyserial-3.5-py2.py3-none-any.whl"

PI_USER = "pi"
PI_PASS = "prezio2026"
PI_HOSTNAME = "prezio-recorder"
WIFI_SSID = "Prezio-Recorder"
WIFI_PASS = "prezio2026"

COL_BG       = "#1a1a2e"
COL_SURFACE  = "#16213e"
COL_CARD     = "#0f3460"
COL_PRIMARY  = "#1565C0"
COL_ACCENT   = "#42A5F5"
COL_SUCCESS  = "#4CAF50"
COL_ERROR    = "#E53935"
COL_WARNING  = "#FFA726"
COL_TEXT     = "#e0e0e0"
COL_TEXT_DIM = "#90a4ae"
COL_WHITE    = "#ffffff"

# ============================================================
# Win32 API for raw disk writing
# ============================================================
kernel32 = ctypes.windll.kernel32

GENERIC_READ       = 0x80000000
GENERIC_WRITE      = 0x40000000
FILE_SHARE_RW      = 0x3
OPEN_EXISTING      = 3
FSCTL_LOCK_VOLUME  = 0x00090018
FSCTL_DISMOUNT     = 0x00090020
FSCTL_UNLOCK       = 0x0009001C
INVALID_HANDLE     = ctypes.wintypes.HANDLE(-1).value

def open_disk(path):
    h = kernel32.CreateFileW(path, GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_RW, None, OPEN_EXISTING, 0, None)
    if h == INVALID_HANDLE:
        raise OSError(f"Cannot open {path}: error {ctypes.GetLastError()}")
    return h

def close_disk(h):
    kernel32.CloseHandle(h)

def lock_and_dismount(h):
    out = ctypes.wintypes.DWORD()
    kernel32.DeviceIoControl(h, FSCTL_LOCK_VOLUME, None, 0, None, 0, ctypes.byref(out), None)
    kernel32.DeviceIoControl(h, FSCTL_DISMOUNT, None, 0, None, 0, ctypes.byref(out), None)

def unlock_disk(h):
    out = ctypes.wintypes.DWORD()
    kernel32.DeviceIoControl(h, FSCTL_UNLOCK, None, 0, None, 0, ctypes.byref(out), None)

def write_chunk(h, data):
    size = len(data)
    if size % 512 != 0:
        size = ((size // 512) + 1) * 512
        data = data + b'\x00' * (size - len(data))
    written = ctypes.wintypes.DWORD()
    ok = kernel32.WriteFile(h, data, size, ctypes.byref(written), None)
    if not ok:
        raise OSError(f"WriteFile failed: error {ctypes.GetLastError()}")
    return written.value

# ============================================================
# Disk enumeration via WMI (PowerShell)
# ============================================================
def get_removable_disks():
    ps = (
        "Get-Disk | Where-Object { "
        "($_.BusType -eq 'USB' -or $_.BusType -eq 'SD') -and $_.Size -gt 1GB -and $_.Size -lt 128GB "
        "} | Select-Object Number, FriendlyName, Size, BusType | ConvertTo-Json"
    )
    try:
        r = subprocess.run(["powershell", "-NoProfile", "-Command", ps],
            capture_output=True, text=True, timeout=15)
        if r.returncode != 0 or not r.stdout.strip():
            return []
        data = json.loads(r.stdout)
        if isinstance(data, dict):
            data = [data]
        return data
    except Exception:
        return []

def get_boot_drive_letter(disk_num):
    ps = (
        f"$p = Get-Partition -DiskNumber {disk_num} -ErrorAction SilentlyContinue | "
        "Where-Object { $_.Size -lt 1GB -and $_.Size -gt 50MB } | Select-Object -First 1; "
        "if ($p -and $p.DriveLetter) { $p.DriveLetter } "
        "elseif ($p) { "
        "$free = 67..90 | ForEach-Object { [char]$_ } | Where-Object { -not (Test-Path \"${_}:\\\") } | Select-Object -Last 1; "
        "$p | Set-Partition -NewDriveLetter $free -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1; $free "
        "}"
    )
    try:
        r = subprocess.run(["powershell", "-NoProfile", "-Command", ps],
            capture_output=True, text=True, timeout=20)
        letter = r.stdout.strip()
        if letter and len(letter) == 1 and os.path.exists(f"{letter}:\\config.txt"):
            return letter
    except Exception:
        pass
    return None

# ============================================================
# Firstrun script content
# ============================================================
def make_firstrun_sh():
    return f"""#!/bin/bash
set +e

LOG=/var/log/prezio-firstboot.log
exec > >(tee -a "$LOG") 2>&1

echo "==== Prezio First Boot - $(date) ===="

FIRSTUSER=$(getent passwd 1000 | cut -d: -f1)
if [ -z "$FIRSTUSER" ]; then
    useradd -m -G sudo,adm,dialout,audio,video,plugdev,games,users,input,netdev,gpio,i2c,spi pi
fi
echo "pi:{PI_PASS}" | chpasswd

echo "{PI_HOSTNAME}" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\\t{PI_HOSTNAME}/" /etc/hosts

systemctl enable ssh
systemctl start ssh

sleep 5

SRC=/boot/firmware/prezio_setup
DST=/home/pi/prezio-v2/pi_recorder
mkdir -p $DST
cp $SRC/pi_recorder.py $DST/
cp $SRC/setup_pi.sh $DST/
cp $SRC/requirements.txt $DST/
cp $SRC/howto.txt $DST/ 2>/dev/null
cp $SRC/pyserial-*.whl $DST/ 2>/dev/null
chown -R pi:pi /home/pi/prezio-v2

cd $DST
bash setup_pi.sh

rm -rf /boot/firmware/prezio_setup
rm -f /boot/firmware/firstrun.sh
sed -i 's| systemd.run.*||g' /boot/firmware/cmdline.txt

echo "==== Prezio First Boot COMPLETE ===="
exit 0
"""

# ============================================================
# GUI Application
# ============================================================
class PrezioImager(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("PrezioImager")
        self.geometry("520x640")
        self.resizable(False, False)
        self.configure(bg=COL_BG)

        self.script_dir = self._get_script_dir()
        self.cache_dir = os.path.join(self.script_dir, ".flash_cache")
        os.makedirs(self.cache_dir, exist_ok=True)

        self.disks = []
        self.flashing = False

        self._build_ui()
        self._refresh_disks()

    def _get_script_dir(self):
        if getattr(sys, 'frozen', False):
            return os.path.dirname(sys.executable)
        return os.path.dirname(os.path.abspath(__file__))

    # ---- UI ----
    def _build_ui(self):
        # Header
        hdr = tk.Frame(self, bg=COL_SURFACE, height=80)
        hdr.pack(fill="x")
        hdr.pack_propagate(False)

        tk.Label(hdr, text="PrezioImager", font=("Segoe UI", 22, "bold"),
                 bg=COL_SURFACE, fg=COL_WHITE).pack(side="left", padx=20, pady=15)
        tk.Label(hdr, text="Soleco AG", font=("Segoe UI", 10),
                 bg=COL_SURFACE, fg=COL_TEXT_DIM).pack(side="left", pady=15)
        tk.Label(hdr, text="Pi Zero 2 W", font=("Segoe UI", 10),
                 bg=COL_SURFACE, fg=COL_ACCENT).pack(side="right", padx=20, pady=15)

        # Separator
        tk.Frame(self, bg=COL_PRIMARY, height=3).pack(fill="x")

        # Main content
        main = tk.Frame(self, bg=COL_BG, padx=24, pady=16)
        main.pack(fill="both", expand=True)

        # --- SD Card selection ---
        self._section_label(main, "SD-KARTE")

        disk_frame = tk.Frame(main, bg=COL_CARD, highlightbackground=COL_PRIMARY,
                              highlightthickness=1)
        disk_frame.pack(fill="x", pady=(4, 0))

        self.disk_listbox = tk.Listbox(disk_frame, height=4, font=("Consolas", 11),
            bg=COL_CARD, fg=COL_TEXT, selectbackground=COL_PRIMARY,
            selectforeground=COL_WHITE, borderwidth=0, highlightthickness=0,
            activestyle="none")
        self.disk_listbox.pack(fill="x", padx=8, pady=8)

        btn_frame = tk.Frame(main, bg=COL_BG)
        btn_frame.pack(fill="x", pady=(8, 0))

        self.refresh_btn = tk.Button(btn_frame, text="Aktualisieren",
            font=("Segoe UI", 10), bg=COL_CARD, fg=COL_TEXT,
            activebackground=COL_PRIMARY, activeforeground=COL_WHITE,
            borderwidth=0, padx=16, pady=6, cursor="hand2",
            command=self._refresh_disks)
        self.refresh_btn.pack(side="left")

        # --- Info ---
        self._section_label(main, "KONFIGURATION", top=16)

        info_frame = tk.Frame(main, bg=COL_CARD, highlightbackground="#2a2a4a",
                              highlightthickness=1)
        info_frame.pack(fill="x", pady=(4, 0))

        infos = [
            ("WiFi SSID:", WIFI_SSID),
            ("WiFi Passwort:", WIFI_PASS),
            ("SSH User:", f"{PI_USER} / {PI_PASS}"),
            ("IP-Adresse:", "192.168.4.1"),
            ("HTTP API:", "http://192.168.4.1:8080"),
        ]
        for label, value in infos:
            row = tk.Frame(info_frame, bg=COL_CARD)
            row.pack(fill="x", padx=12, pady=2)
            tk.Label(row, text=label, font=("Segoe UI", 9),
                     bg=COL_CARD, fg=COL_TEXT_DIM, width=16, anchor="w").pack(side="left")
            tk.Label(row, text=value, font=("Segoe UI", 9, "bold"),
                     bg=COL_CARD, fg=COL_TEXT, anchor="w").pack(side="left")
        tk.Frame(info_frame, bg=COL_CARD, height=6).pack()

        # --- Progress ---
        self._section_label(main, "FORTSCHRITT", top=16)

        self.progress_var = tk.DoubleVar(value=0)
        style = ttk.Style()
        style.theme_use('default')
        style.configure("Custom.Horizontal.TProgressbar",
            troughcolor=COL_CARD, background=COL_PRIMARY,
            borderwidth=0, lightcolor=COL_PRIMARY, darkcolor=COL_PRIMARY)

        self.progress_bar = ttk.Progressbar(main, variable=self.progress_var,
            maximum=100, style="Custom.Horizontal.TProgressbar", length=470)
        self.progress_bar.pack(fill="x", pady=(4, 0))

        self.status_label = tk.Label(main, text="Bereit",
            font=("Segoe UI", 10), bg=COL_BG, fg=COL_TEXT_DIM, anchor="w")
        self.status_label.pack(fill="x", pady=(4, 0))

        # --- Flash button ---
        tk.Frame(main, bg=COL_BG, height=12).pack()

        self.flash_btn = tk.Button(main, text="SD-KARTE FLASHEN",
            font=("Segoe UI", 14, "bold"), bg=COL_PRIMARY, fg=COL_WHITE,
            activebackground=COL_ACCENT, activeforeground=COL_WHITE,
            borderwidth=0, padx=32, pady=12, cursor="hand2",
            command=self._on_flash)
        self.flash_btn.pack(fill="x")

        # Footer
        footer = tk.Frame(self, bg=COL_SURFACE, height=32)
        footer.pack(fill="x", side="bottom")
        footer.pack_propagate(False)
        tk.Label(footer, text="SD rein  >  Flashen  >  In Pi stecken  >  Fertig",
                 font=("Segoe UI", 9), bg=COL_SURFACE, fg=COL_TEXT_DIM).pack(pady=6)

    def _section_label(self, parent, text, top=0):
        tk.Label(parent, text=text, font=("Segoe UI", 8, "bold"),
                 bg=COL_BG, fg=COL_ACCENT).pack(fill="x", pady=(top, 0), anchor="w")

    # ---- Disk handling ----
    def _refresh_disks(self):
        self.disk_listbox.delete(0, tk.END)
        self.disks = get_removable_disks()
        if not self.disks:
            self.disk_listbox.insert(0, "  Keine SD-Karte gefunden. Einstecken & Aktualisieren.")
        else:
            for d in self.disks:
                size_gb = round(d['Size'] / (1024**3), 1)
                self.disk_listbox.insert(tk.END,
                    f"  Disk {d['Number']}:  {size_gb} GB  -  {d['FriendlyName']}")
            self.disk_listbox.selection_set(0)

    # ---- Flash process ----
    def _on_flash(self):
        if self.flashing:
            return
        if not self.disks:
            messagebox.showwarning("Keine SD-Karte", "Bitte SD-Karte einstecken und Aktualisieren.")
            return

        sel = self.disk_listbox.curselection()
        if not sel:
            messagebox.showwarning("Auswahl", "Bitte eine SD-Karte auswaehlen.")
            return

        disk = self.disks[sel[0]]
        size_gb = round(disk['Size'] / (1024**3), 1)

        confirm = messagebox.askokcancel("Achtung!",
            f"Disk {disk['Number']} ({size_gb} GB - {disk['FriendlyName']})\n\n"
            "ALLE DATEN WERDEN GELOESCHT!\n\n"
            "Fortfahren?",
            icon="warning")
        if not confirm:
            return

        self.flashing = True
        self.flash_btn.configure(state="disabled", bg="#555555")
        self.refresh_btn.configure(state="disabled")
        threading.Thread(target=self._flash_worker, args=(disk,), daemon=True).start()

    def _set_status(self, text, color=COL_TEXT_DIM):
        self.after(0, lambda: self.status_label.configure(text=text, fg=color))

    def _set_progress(self, val):
        self.after(0, lambda: self.progress_var.set(val))

    def _flash_done(self, success, msg=""):
        def _do():
            self.flashing = False
            self.flash_btn.configure(state="normal", bg=COL_PRIMARY)
            self.refresh_btn.configure(state="normal")
            if success:
                self._set_status("Fertig!", COL_SUCCESS)
                self._set_progress(100)
                messagebox.showinfo("Fertig!",
                    "SD-Karte ist bereit!\n\n"
                    "1. SD-Karte auswerfen\n"
                    "2. In den Pi Zero 2 W stecken\n"
                    "3. Strom anschliessen\n"
                    "4. 3-5 Minuten warten\n"
                    f"5. WiFi '{WIFI_SSID}' verbinden\n"
                    f"   Passwort: {WIFI_PASS}\n"
                    "6. http://192.168.4.1:8080 testen")
            else:
                self._set_status(f"Fehler: {msg}", COL_ERROR)
                messagebox.showerror("Fehler", msg)
        self.after(0, _do)

    def _flash_worker(self, disk):
        disk_num = disk['Number']
        try:
            # --- Step 1: Download / cache image ---
            img_path = os.path.join(self.cache_dir, PI_OS_IMG)
            if not os.path.exists(img_path):
                xz_path = os.path.join(self.cache_dir, PI_OS_XZ)
                if not os.path.exists(xz_path):
                    self._set_status("Lade Raspberry Pi OS herunter (~430 MB)...")
                    self._set_progress(0)
                    self._download_file(PI_OS_URL, xz_path)

                self._set_status("Entpacke Image (das dauert 1-2 Min)...")
                self._set_progress(0)
                self._extract_xz(xz_path, img_path)
                try:
                    os.remove(xz_path)
                except OSError:
                    pass

            # --- Step 1b: Download pyserial wheel ---
            whl_path = os.path.join(self.cache_dir, PYSERIAL_WHL)
            if not os.path.exists(whl_path):
                try:
                    self._set_status("Lade pyserial...")
                    req = Request(PYSERIAL_URL, headers={"User-Agent": "PrezioImager/1.0"})
                    with urlopen(req, timeout=30) as resp:
                        with open(whl_path, "wb") as f:
                            f.write(resp.read())
                except Exception:
                    whl_path = None

            # --- Step 2: Clean disk ---
            self._set_status("Bereite SD-Karte vor...")
            self._set_progress(25)
            subprocess.run(
                ["powershell", "-NoProfile", "-Command",
                 f"'select disk {disk_num}\nclean' | diskpart"],
                capture_output=True, timeout=30)
            import time; time.sleep(2)

            # --- Step 3: Write image ---
            self._set_status("Schreibe Image auf SD-Karte...")
            self._write_image(disk_num, img_path)

            # --- Step 4: Configure boot partition ---
            self._set_status("Konfiguriere Boot-Partition...")
            self._set_progress(90)

            subprocess.run(
                ["powershell", "-NoProfile", "-Command", "echo rescan | diskpart"],
                capture_output=True, timeout=15)
            import time; time.sleep(4)

            boot_letter = None
            for _ in range(15):
                boot_letter = get_boot_drive_letter(disk_num)
                if boot_letter:
                    break
                import time; time.sleep(2)

            if not boot_letter:
                self._flash_done(False, "Boot-Partition konnte nicht gefunden werden.")
                return

            boot_root = f"{boot_letter}:\\"
            self._configure_boot(boot_root, whl_path)

            self._set_progress(100)
            self._flash_done(True)

        except Exception as e:
            self._flash_done(False, str(e))

    def _download_file(self, url, dest):
        req = Request(url, headers={"User-Agent": "PrezioImager/1.0"})
        with urlopen(req, timeout=600) as resp:
            total = int(resp.headers.get('Content-Length', 0))
            downloaded = 0
            chunk_size = 256 * 1024
            with open(dest, "wb") as f:
                while True:
                    chunk = resp.read(chunk_size)
                    if not chunk:
                        break
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total > 0:
                        pct = min(24, int(downloaded / total * 24))
                        self._set_progress(pct)
                        mb = downloaded // (1024 * 1024)
                        total_mb = total // (1024 * 1024)
                        self._set_status(f"Lade Pi OS herunter... {mb}/{total_mb} MB")

    def _extract_xz(self, xz_path, img_path):
        with lzma.open(xz_path) as xz_in:
            with open(img_path, "wb") as img_out:
                total_written = 0
                while True:
                    chunk = xz_in.read(4 * 1024 * 1024)
                    if not chunk:
                        break
                    img_out.write(chunk)
                    total_written += len(chunk)
                    mb = total_written // (1024 * 1024)
                    self._set_status(f"Entpacke... {mb} MB")

    def _write_image(self, disk_num, img_path):
        phys = f"\\\\.\\PhysicalDrive{disk_num}"
        img_size = os.path.getsize(img_path)
        buf_size = 1024 * 1024

        h = open_disk(phys)
        try:
            lock_and_dismount(h)
            written = 0
            with open(img_path, "rb") as img:
                while True:
                    data = img.read(buf_size)
                    if not data:
                        break
                    write_chunk(h, data)
                    written += len(data)
                    pct = 25 + int(written / img_size * 60)
                    self._set_progress(min(pct, 85))
                    mb = written // (1024 * 1024)
                    total_mb = img_size // (1024 * 1024)
                    self._set_status(f"Schreibe... {mb}/{total_mb} MB")
            unlock_disk(h)
        finally:
            close_disk(h)

    def _configure_boot(self, boot_root, whl_path):
        setup_dir = os.path.join(boot_root, "prezio_setup")
        os.makedirs(setup_dir, exist_ok=True)

        # Enable SSH
        open(os.path.join(boot_root, "ssh"), "w").close()

        # Copy prezio files
        for fname in ["pi_recorder.py", "setup_pi.sh", "requirements.txt", "howto.txt"]:
            src = os.path.join(self.script_dir, fname)
            if os.path.exists(src):
                dst = os.path.join(setup_dir, fname)
                with open(src, "rb") as f_in:
                    with open(dst, "wb") as f_out:
                        f_out.write(f_in.read())

        if whl_path and os.path.exists(whl_path):
            dst = os.path.join(setup_dir, PYSERIAL_WHL)
            with open(whl_path, "rb") as f_in:
                with open(dst, "wb") as f_out:
                    f_out.write(f_in.read())

        # Write firstrun.sh (LF line endings)
        firstrun_path = os.path.join(boot_root, "firstrun.sh")
        with open(firstrun_path, "wb") as f:
            f.write(make_firstrun_sh().encode("utf-8"))

        # Modify cmdline.txt
        cmdline_path = os.path.join(boot_root, "cmdline.txt")
        if os.path.exists(cmdline_path):
            with open(cmdline_path, "r") as f:
                cmdline = f.read().strip()
            if "systemd.run=" not in cmdline:
                cmdline += (" systemd.run=/boot/firmware/firstrun.sh"
                           " systemd.run_success_action=reboot"
                           " systemd.unit=kernel-command-line.target")
                with open(cmdline_path, "wb") as f:
                    f.write((cmdline + "\n").encode("utf-8"))

# ============================================================
# Admin check & entry point
# ============================================================
def is_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except Exception:
        return False

def run_as_admin():
    ctypes.windll.shell32.ShellExecuteW(
        None, "runas", sys.executable,
        f'"{os.path.abspath(__file__)}"', None, 1)

if __name__ == "__main__":
    if not is_admin():
        run_as_admin()
        sys.exit(0)

    app = PrezioImager()
    app.mainloop()
