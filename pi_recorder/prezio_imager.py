"""
PrezioImager - All-in-one SD-Karten Flash Tool fuer Pi Zero 2 W
Soleco AG
"""

import ctypes
import ctypes.wintypes
import json
import lzma
import os
import subprocess
import sys
import threading
import time
import tkinter as tk
from tkinter import ttk, messagebox
from urllib.request import urlopen, Request

# ============================================================
# Config
# ============================================================
PI_OS_URL = "https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2025-05-13/2025-05-13-raspios-bookworm-arm64-lite.img.xz"
PI_OS_XZ = "2025-05-13-raspios-bookworm-arm64-lite.img.xz"
PI_OS_IMG = "2025-05-13-raspios-bookworm-arm64-lite.img"
PYSERIAL_URL = "https://files.pythonhosted.org/packages/07/bc/587a445451b253b285629263eb51c2d8e9bcea4fc97826266d186f96f558/pyserial-3.5-py2.py3-none-any.whl"
PYSERIAL_WHL = "pyserial-3.5-py2.py3-none-any.whl"

PI_USER     = "preziouser"
PI_PASS     = "Prezio2000!"
PI_HOSTNAME = "prezio-recorder"
WIFI_SSID   = "Prezio-Recorder"
WIFI_PASS   = "prezio2026"

# Kolibri Design: Orange + Weiss
COL_BG        = "#FAFAFA"
COL_SURFACE   = "#FFFFFF"
COL_CARD      = "#FFFFFF"
COL_CARD_BDR  = "#E0E0E0"
COL_PRIMARY   = "#F57C00"
COL_PRIMARY_D = "#E65100"
COL_ACCENT    = "#FF9800"
COL_SUCCESS   = "#43A047"
COL_ERROR     = "#D32F2F"
COL_TEXT      = "#212121"
COL_TEXT_SEC  = "#616161"
COL_TEXT_DIM  = "#9E9E9E"
COL_WHITE     = "#FFFFFF"
COL_HDR_BG    = "#F57C00"

# Hide all PowerShell/console popups
_NO_WINDOW = 0x08000000

def _si_hidden():
    si = subprocess.STARTUPINFO()
    si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    si.wShowWindow = 0
    return si

def _run_ps(cmd, timeout=20):
    return subprocess.run(
        ["powershell", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", cmd],
        capture_output=True, text=True, timeout=timeout,
        creationflags=_NO_WINDOW, startupinfo=_si_hidden())

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
# Disk enumeration (hidden PowerShell)
# ============================================================
def get_removable_disks():
    ps = (
        "Get-Disk | Where-Object { "
        "($_.BusType -eq 'USB' -or $_.BusType -eq 'SD') -and $_.Size -gt 1GB -and $_.Size -lt 128GB "
        "} | Select-Object Number, FriendlyName, Size, BusType | ConvertTo-Json"
    )
    try:
        r = _run_ps(ps, timeout=15)
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
        r = _run_ps(ps, timeout=20)
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
    useradd -m -G sudo,adm,dialout,audio,video,plugdev,games,users,input,netdev,gpio,i2c,spi {PI_USER}
fi
echo "{PI_USER}:{PI_PASS}" | chpasswd

echo "{PI_HOSTNAME}" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\\t{PI_HOSTNAME}/" /etc/hosts

systemctl enable ssh
systemctl start ssh

sleep 5

SRC=/boot/firmware/prezio_setup
DST=/home/{PI_USER}/prezio-v2/pi_recorder
mkdir -p $DST
cp $SRC/pi_recorder.py $DST/
cp $SRC/setup_pi.sh $DST/
cp $SRC/requirements.txt $DST/
cp $SRC/howto.txt $DST/ 2>/dev/null
cp $SRC/pyserial-*.whl $DST/ 2>/dev/null
chown -R {PI_USER}:{PI_USER} /home/{PI_USER}/prezio-v2

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
        self.title("PrezioImager - Soleco AG")
        self.geometry("540x680")
        self.resizable(False, False)
        self.configure(bg=COL_BG)

        self.script_dir = self._get_script_dir()
        self.cache_dir = os.path.join(self.script_dir, ".flash_cache")
        os.makedirs(self.cache_dir, exist_ok=True)

        self.disks = []
        self.flashing = False

        self._build_ui()
        threading.Thread(target=self._refresh_disks_async, daemon=True).start()

    def _get_script_dir(self):
        if getattr(sys, 'frozen', False):
            return os.path.dirname(sys.executable)
        return os.path.dirname(os.path.abspath(__file__))

    def _build_ui(self):
        # ---- Header bar (orange) ----
        hdr = tk.Frame(self, bg=COL_HDR_BG, height=70)
        hdr.pack(fill="x")
        hdr.pack_propagate(False)

        hdr_inner = tk.Frame(hdr, bg=COL_HDR_BG)
        hdr_inner.pack(fill="both", expand=True, padx=24)

        tk.Label(hdr_inner, text="PrezioImager", font=("Segoe UI", 24, "bold"),
                 bg=COL_HDR_BG, fg=COL_WHITE).pack(side="left", pady=12)

        right_hdr = tk.Frame(hdr_inner, bg=COL_HDR_BG)
        right_hdr.pack(side="right", pady=12)
        tk.Label(right_hdr, text="Soleco AG", font=("Segoe UI", 10, "bold"),
                 bg=COL_HDR_BG, fg=COL_WHITE).pack(anchor="e")
        tk.Label(right_hdr, text="Pi Zero 2 W", font=("Segoe UI", 9),
                 bg=COL_HDR_BG, fg="#FFE0B2").pack(anchor="e")

        # ---- Main content ----
        main = tk.Frame(self, bg=COL_BG, padx=24, pady=20)
        main.pack(fill="both", expand=True)

        # --- SD Card selection ---
        self._section_label(main, "SD-KARTE AUSWAEHLEN")

        card1 = tk.Frame(main, bg=COL_CARD, highlightbackground=COL_CARD_BDR,
                         highlightthickness=1, bd=0)
        card1.pack(fill="x", pady=(6, 0))

        self.disk_listbox = tk.Listbox(card1, height=3, font=("Segoe UI", 11),
            bg=COL_CARD, fg=COL_TEXT, selectbackground=COL_PRIMARY,
            selectforeground=COL_WHITE, borderwidth=0, highlightthickness=0,
            activestyle="none")
        self.disk_listbox.pack(fill="x", padx=10, pady=10)

        btn_frame = tk.Frame(main, bg=COL_BG)
        btn_frame.pack(fill="x", pady=(8, 0))

        self.refresh_btn = tk.Button(btn_frame, text="Aktualisieren",
            font=("Segoe UI", 10), bg=COL_WHITE, fg=COL_TEXT,
            activebackground="#FFF3E0", activeforeground=COL_TEXT,
            borderwidth=1, relief="solid", padx=14, pady=5, cursor="hand2",
            command=self._on_refresh)
        self.refresh_btn.pack(side="left")

        # --- Config info ---
        self._section_label(main, "KONFIGURATION", top=18)

        card2 = tk.Frame(main, bg=COL_CARD, highlightbackground=COL_CARD_BDR,
                         highlightthickness=1, bd=0)
        card2.pack(fill="x", pady=(6, 0))

        infos = [
            ("WiFi SSID:", WIFI_SSID),
            ("WiFi Passwort:", WIFI_PASS),
            ("SSH User:", PI_USER),
            ("SSH Passwort:", PI_PASS),
            ("Pi IP-Adresse:", "192.168.4.1"),
            ("HTTP API:", "http://192.168.4.1:8080"),
        ]
        for i, (label, value) in enumerate(infos):
            row_bg = "#FFF8F0" if i % 2 == 0 else COL_CARD
            row = tk.Frame(card2, bg=row_bg)
            row.pack(fill="x")
            tk.Label(row, text=label, font=("Segoe UI", 9),
                     bg=row_bg, fg=COL_TEXT_SEC, width=16, anchor="w").pack(side="left", padx=(12, 0), pady=3)
            tk.Label(row, text=value, font=("Segoe UI", 9, "bold"),
                     bg=row_bg, fg=COL_TEXT, anchor="w").pack(side="left", pady=3)
        tk.Frame(card2, bg=COL_CARD, height=4).pack()

        # --- Progress ---
        self._section_label(main, "FORTSCHRITT", top=18)

        self.progress_var = tk.DoubleVar(value=0)
        style = ttk.Style()
        style.theme_use('default')
        style.configure("Orange.Horizontal.TProgressbar",
            troughcolor="#E0E0E0", background=COL_PRIMARY,
            borderwidth=0, lightcolor=COL_ACCENT, darkcolor=COL_PRIMARY_D)

        self.progress_bar = ttk.Progressbar(main, variable=self.progress_var,
            maximum=100, style="Orange.Horizontal.TProgressbar")
        self.progress_bar.pack(fill="x", pady=(6, 0), ipady=2)

        self.status_label = tk.Label(main, text="Bereit",
            font=("Segoe UI", 10), bg=COL_BG, fg=COL_TEXT_SEC, anchor="w")
        self.status_label.pack(fill="x", pady=(4, 0))

        # --- Flash button ---
        tk.Frame(main, bg=COL_BG, height=14).pack()

        self.flash_btn = tk.Button(main, text="SD-KARTE FLASHEN",
            font=("Segoe UI", 15, "bold"), bg=COL_PRIMARY, fg=COL_WHITE,
            activebackground=COL_PRIMARY_D, activeforeground=COL_WHITE,
            borderwidth=0, padx=32, pady=14, cursor="hand2",
            command=self._on_flash)
        self.flash_btn.pack(fill="x")

        # ---- Footer ----
        footer = tk.Frame(self, bg="#FFF3E0", height=36)
        footer.pack(fill="x", side="bottom")
        footer.pack_propagate(False)
        tk.Label(footer, text="SD rein  \u2192  Flashen  \u2192  In Pi stecken  \u2192  Fertig",
                 font=("Segoe UI", 9), bg="#FFF3E0", fg=COL_TEXT_SEC).pack(pady=8)

    def _section_label(self, parent, text, top=0):
        tk.Label(parent, text=text, font=("Segoe UI", 8, "bold"),
                 bg=COL_BG, fg=COL_PRIMARY).pack(fill="x", pady=(top, 0), anchor="w")

    # ---- Disk handling (async, no popup) ----
    def _on_refresh(self):
        if self.flashing:
            return
        self.refresh_btn.configure(state="disabled")
        self.disk_listbox.delete(0, tk.END)
        self.disk_listbox.insert(0, "  Suche SD-Karten...")
        threading.Thread(target=self._refresh_disks_async, daemon=True).start()

    def _refresh_disks_async(self):
        disks = get_removable_disks()
        self.after(0, lambda: self._update_disk_list(disks))

    def _update_disk_list(self, disks):
        self.disks = disks
        self.disk_listbox.delete(0, tk.END)
        if not disks:
            self.disk_listbox.insert(0, "  Keine SD-Karte gefunden. Einstecken & Aktualisieren.")
        else:
            for d in disks:
                size_gb = round(d['Size'] / (1024**3), 1)
                self.disk_listbox.insert(tk.END,
                    f"  Disk {d['Number']}:  {size_gb} GB  \u2013  {d['FriendlyName']}")
            self.disk_listbox.selection_set(0)
        self.refresh_btn.configure(state="normal")

    # ---- Flash process ----
    def _on_flash(self):
        if self.flashing:
            return
        if not self.disks:
            messagebox.showwarning("Keine SD-Karte", "Bitte SD-Karte einstecken und Aktualisieren klicken.")
            return

        sel = self.disk_listbox.curselection()
        if not sel:
            messagebox.showwarning("Auswahl", "Bitte eine SD-Karte auswaehlen.")
            return

        disk = self.disks[sel[0]]
        size_gb = round(disk['Size'] / (1024**3), 1)

        confirm = messagebox.askokcancel("Achtung!",
            f"Disk {disk['Number']} ({size_gb} GB \u2013 {disk['FriendlyName']})\n\n"
            "ALLE DATEN WERDEN GELOESCHT!\n\n"
            "Fortfahren?",
            icon="warning")
        if not confirm:
            return

        self.flashing = True
        self.flash_btn.configure(state="disabled", bg="#BDBDBD", fg="#757575")
        self.refresh_btn.configure(state="disabled")
        threading.Thread(target=self._flash_worker, args=(disk,), daemon=True).start()

    def _set_status(self, text, color=COL_TEXT_SEC):
        self.after(0, lambda: self.status_label.configure(text=text, fg=color))

    def _set_progress(self, val):
        self.after(0, lambda: self.progress_var.set(val))

    def _flash_done(self, success, msg=""):
        def _do():
            self.flashing = False
            self.flash_btn.configure(state="normal", bg=COL_PRIMARY, fg=COL_WHITE)
            self.refresh_btn.configure(state="normal")
            if success:
                self._set_status("Fertig!", COL_SUCCESS)
                self._set_progress(100)
                messagebox.showinfo("Fertig!",
                    "SD-Karte ist bereit!\n\n"
                    "1. SD-Karte sicher auswerfen\n"
                    "2. In den Pi Zero 2 W stecken\n"
                    "3. Strom anschliessen\n"
                    "4. 3\u20135 Minuten warten\n"
                    f"5. WiFi \"{WIFI_SSID}\" verbinden\n"
                    f"    Passwort: {WIFI_PASS}\n\n"
                    f"SSH: ssh {PI_USER}@192.168.4.1\n"
                    f"Passwort: {PI_PASS}")
            else:
                self._set_status(f"Fehler: {msg}", COL_ERROR)
                messagebox.showerror("Fehler", msg)
        self.after(0, _do)

    def _flash_worker(self, disk):
        disk_num = disk['Number']
        try:
            img_path = os.path.join(self.cache_dir, PI_OS_IMG)
            if not os.path.exists(img_path):
                xz_path = os.path.join(self.cache_dir, PI_OS_XZ)
                if not os.path.exists(xz_path):
                    self._set_status("Lade Raspberry Pi OS herunter (~430 MB)...")
                    self._set_progress(0)
                    self._download_file(PI_OS_URL, xz_path)

                self._set_status("Entpacke Image (1\u20132 Min)...")
                self._set_progress(0)
                self._extract_xz(xz_path, img_path)
                try:
                    os.remove(xz_path)
                except OSError:
                    pass

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

            self._set_status("Bereite SD-Karte vor...")
            self._set_progress(25)
            _run_ps(f"'select disk {disk_num}\nclean' | diskpart", timeout=30)
            time.sleep(2)

            self._set_status("Schreibe Image auf SD-Karte...")
            self._write_image(disk_num, img_path)

            self._set_status("Konfiguriere Boot-Partition...")
            self._set_progress(90)

            _run_ps("echo rescan | diskpart", timeout=15)
            time.sleep(4)

            boot_letter = None
            for _ in range(15):
                boot_letter = get_boot_drive_letter(disk_num)
                if boot_letter:
                    break
                time.sleep(2)

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
            with open(dest, "wb") as f:
                while True:
                    chunk = resp.read(256 * 1024)
                    if not chunk:
                        break
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total > 0:
                        pct = min(24, int(downloaded / total * 24))
                        self._set_progress(pct)
                        mb = downloaded // (1024 * 1024)
                        total_mb = total // (1024 * 1024)
                        self._set_status(f"Lade Pi OS... {mb}/{total_mb} MB")

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

        h = open_disk(phys)
        try:
            lock_and_dismount(h)
            written = 0
            with open(img_path, "rb") as img:
                while True:
                    data = img.read(1024 * 1024)
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

        open(os.path.join(boot_root, "ssh"), "w").close()

        for fname in ["pi_recorder.py", "setup_pi.sh", "requirements.txt", "howto.txt"]:
            src = os.path.join(self.script_dir, fname)
            if os.path.exists(src):
                with open(src, "rb") as f_in:
                    with open(os.path.join(setup_dir, fname), "wb") as f_out:
                        f_out.write(f_in.read())

        if whl_path and os.path.exists(whl_path):
            with open(whl_path, "rb") as f_in:
                with open(os.path.join(setup_dir, PYSERIAL_WHL), "wb") as f_out:
                    f_out.write(f_in.read())

        with open(os.path.join(boot_root, "firstrun.sh"), "wb") as f:
            f.write(make_firstrun_sh().encode("utf-8"))

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
    if getattr(sys, 'frozen', False):
        exe = sys.executable
    else:
        exe = sys.executable
    script = os.path.abspath(__file__) if not getattr(sys, 'frozen', False) else ""
    args = f'"{script}"' if script else ""
    ctypes.windll.shell32.ShellExecuteW(None, "runas", exe, args, None, 1)

if __name__ == "__main__":
    if not is_admin():
        run_as_admin()
        sys.exit(0)

    app = PrezioImager()
    app.mainloop()
