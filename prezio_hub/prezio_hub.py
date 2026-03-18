"""
PrezioHub - Zentrale Steuerung fuer das Prezio-Oekosystem
Soleco AG
"""

import json
import os
import re
import subprocess
import sys
import shutil
import threading
import time
import tkinter as tk
import zipfile
from tkinter import ttk, messagebox, filedialog
from urllib.request import urlopen, Request
from urllib.error import URLError
from datetime import datetime
from io import BytesIO

try:
    import paramiko
    HAS_PARAMIKO = True
except ImportError:
    HAS_PARAMIKO = False

# ============================================================
# Config
# ============================================================
VERSION     = "1.1.0"
GITHUB_RAW  = "https://raw.githubusercontent.com/someFisherman/prezio-v2/main/pi_recorder"
GITHUB_FW_FILES = ["pi_recorder.py", "setup_pi.sh", "requirements.txt", "howto.txt"]

PI_IP       = "192.168.4.1"
PI_PORT     = 8080
PI_USER     = "pi"
PI_PASS     = "Prezio2000!"
PI_HOSTNAME = "prezio-recorder"
WIFI_SSID   = "Prezio-Recorder"

SUPABASE_URL  = "https://ndqisdqdhzeenvjkkuxd.supabase.co"
SUPABASE_KEY  = "sb_publishable_7_dV2GvFjTKAu3cH9XPTXg_L69KyAT_"
SUPABASE_BUCKET = "protokolle"
SUPABASE_DASHBOARD = "https://supabase.com/dashboard/project/ndqisdqdhzeenvjkkuxd"

PI_BASE = f"http://{PI_IP}:{PI_PORT}"

COL_BG        = "#FAFAFA"
COL_CARD      = "#FFFFFF"
COL_CARD_BDR  = "#E0E0E0"
COL_PRIMARY   = "#F57C00"
COL_PRIMARY_D = "#E65100"
COL_ACCENT    = "#FF9800"
COL_SUCCESS   = "#43A047"
COL_ERROR     = "#D32F2F"
COL_WARN      = "#FFA000"
COL_TEXT      = "#212121"
COL_TEXT_SEC  = "#616161"
COL_WHITE     = "#FFFFFF"
COL_HDR_BG    = "#F57C00"

REFRESH_MS = 5000
FIRMWARE_CACHE = os.path.join(
    os.environ.get("LOCALAPPDATA", os.path.expanduser("~")),
    "PrezioHub", "firmware_cache")

def _base_dir():
    """Directory where this exe/script lives (for finding sibling tools)."""
    if getattr(sys, 'frozen', False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))

def _project_root():
    """Dev project root (prezio_v2/) - only relevant when running as .py."""
    if getattr(sys, 'frozen', False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BASE_DIR = _base_dir()
PROJECT_ROOT = _project_root()

# ============================================================
# HTTP helpers
# ============================================================
def _api_get(path, timeout=4):
    try:
        req = Request(f"{PI_BASE}{path}", headers={"User-Agent": "PrezioHub/1.0"})
        with urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except Exception:
        return None

def _api_post(path, body=None, timeout=8):
    try:
        data = json.dumps(body or {}).encode()
        req = Request(f"{PI_BASE}{path}", data=data, method="POST",
                      headers={"User-Agent": "PrezioHub/1.0", "Content-Type": "application/json"})
        with urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        return {"error": str(e)}

def _api_delete(path, timeout=8):
    try:
        req = Request(f"{PI_BASE}{path}", method="DELETE",
                      headers={"User-Agent": "PrezioHub/1.0"})
        with urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        return {"error": str(e)}

def _api_get_text(path, timeout=8):
    try:
        req = Request(f"{PI_BASE}{path}", headers={"User-Agent": "PrezioHub/1.0"})
        with urlopen(req, timeout=timeout) as resp:
            return resp.read().decode()
    except Exception:
        return None

def _supabase_get(table, params="", timeout=8):
    try:
        url = f"{SUPABASE_URL}/rest/v1/{table}?{params}"
        req = Request(url, headers={
            "apikey": SUPABASE_KEY,
            "Authorization": f"Bearer {SUPABASE_KEY}",
            "Accept": "application/json",
        })
        with urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except Exception:
        return None

def _supabase_storage_list(prefix="", timeout=10):
    try:
        url = f"{SUPABASE_URL}/storage/v1/object/list/{SUPABASE_BUCKET}"
        body = json.dumps({
            "prefix": prefix,
            "limit": 200,
            "offset": 0,
            "sortBy": {"column": "created_at", "order": "desc"},
        }).encode()
        req = Request(url, data=body, method="POST", headers={
            "apikey": SUPABASE_KEY,
            "Authorization": f"Bearer {SUPABASE_KEY}",
            "Content-Type": "application/json",
        })
        with urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except Exception:
        return None

def _supabase_storage_download(path, timeout=30):
    try:
        from urllib.parse import quote
        safe_path = quote(path, safe="/")
        url = f"{SUPABASE_URL}/storage/v1/object/{SUPABASE_BUCKET}/{safe_path}"
        req = Request(url, headers={
            "apikey": SUPABASE_KEY,
            "Authorization": f"Bearer {SUPABASE_KEY}",
        })
        with urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except Exception:
        return None

def _ssh_exec(cmd, timeout=15):
    if not HAS_PARAMIKO:
        return None, "paramiko nicht installiert (pip install paramiko)"
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(PI_IP, username=PI_USER, password=PI_PASS,
                       timeout=5, allow_agent=False, look_for_keys=False)
        _, stdout, stderr = client.exec_command(cmd, timeout=timeout)
        out = stdout.read().decode(errors="replace")
        err = stderr.read().decode(errors="replace")
        return out, err
    except paramiko.AuthenticationException:
        return None, f"SSH Authentifizierung fehlgeschlagen.\nUser: {PI_USER} / Pass: {PI_PASS}\nBitte Zugangsdaten pruefen."
    except Exception as e:
        return None, f"SSH Fehler: {e}"
    finally:
        client.close()

def _parse_version(tag):
    """Parse 'v1.2.3' or '1.2.3' into tuple (1,2,3)."""
    tag = str(tag).lstrip("v").strip()
    parts = tag.split(".")
    return tuple(int(p) for p in parts if p.isdigit())

def _read_version_from_py(text):
    """Extract VERSION = '...' from Python source text."""
    m = re.search(r'VERSION\s*=\s*["\']([^"\']+)["\']', text)
    return m.group(1) if m else None

def _cache_firmware():
    """Download pi_recorder firmware files from GitHub main branch."""
    os.makedirs(FIRMWARE_CACHE, exist_ok=True)
    ok = True
    for fname in GITHUB_FW_FILES:
        url = f"{GITHUB_RAW}/{fname}"
        try:
            req = Request(url, headers={"User-Agent": "PrezioHub/1.0"})
            with urlopen(req, timeout=15) as resp:
                data = resp.read()
            with open(os.path.join(FIRMWARE_CACHE, fname), "wb") as f:
                f.write(data)
        except Exception:
            ok = False
    return ok

def _get_cached_firmware_version():
    """Read VERSION from cached pi_recorder.py, or None."""
    path = os.path.join(FIRMWARE_CACHE, "pi_recorder.py")
    if not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            return _read_version_from_py(f.read())
    except Exception:
        return None

def _sftp_upload(local_path, remote_path):
    """Upload a file to the Pi via SFTP. Returns (success, message)."""
    if not HAS_PARAMIKO:
        return False, "paramiko nicht installiert"
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(PI_IP, username=PI_USER, password=PI_PASS,
                       timeout=5, allow_agent=False, look_for_keys=False)
        sftp = client.open_sftp()
        sftp.put(local_path, remote_path)
        sftp.close()
        return True, "Upload OK"
    except paramiko.AuthenticationException:
        return False, f"SSH Authentifizierung fehlgeschlagen (User: {PI_USER})"
    except Exception as e:
        return False, f"SFTP Fehler: {e}"
    finally:
        client.close()

# ============================================================
# Main App
# ============================================================
class PrezioHub(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("PrezioHub - Soleco AG")
        self.geometry("820x700")
        self.minsize(780, 600)
        self.configure(bg=COL_BG)

        ico_path = None
        for d in [getattr(sys, '_MEIPASS', ''), _base_dir(),
                  os.path.dirname(os.path.abspath(__file__))]:
            p = os.path.join(d, "prezio_hub.ico")
            if os.path.exists(p):
                ico_path = p
                break
        if ico_path:
            self.iconbitmap(ico_path)

        self._tool_procs = {}
        self._auto_refresh = True
        self._cached_fw_version = None

        self._build_header()
        self._build_tabs()
        self._schedule_refresh()
        self.protocol("WM_DELETE_WINDOW", self._on_close)

        threading.Thread(target=self._startup_cache_firmware, daemon=True).start()

    # ---- Header ----
    def _build_header(self):
        hdr = tk.Frame(self, bg=COL_HDR_BG, height=60)
        hdr.pack(fill="x")
        hdr.pack_propagate(False)
        inner = tk.Frame(hdr, bg=COL_HDR_BG)
        inner.pack(fill="both", expand=True, padx=20)
        tk.Label(inner, text="PrezioHub", font=("Segoe UI", 22, "bold"),
                 bg=COL_HDR_BG, fg=COL_WHITE).pack(side="left", pady=10)
        right = tk.Frame(inner, bg=COL_HDR_BG)
        right.pack(side="right", pady=10)
        tk.Label(right, text="Soleco AG", font=("Segoe UI", 10, "bold"),
                 bg=COL_HDR_BG, fg=COL_WHITE).pack(anchor="e")
        tk.Label(right, text="Zentrale Steuerung", font=("Segoe UI", 9),
                 bg=COL_HDR_BG, fg="#FFE0B2").pack(anchor="e")

    # ---- Firmware-Cache beim Start aktualisieren ----
    def _startup_cache_firmware(self):
        """Background thread: pull latest firmware files from GitHub main."""
        ok = _cache_firmware()
        ver = _get_cached_firmware_version()
        if ver:
            self.after(0, lambda: setattr(self, '_cached_fw_version', ver))
        if not ok:
            has_cache = ver is not None
            if has_cache:
                self.after(0, lambda: self._show_inet_banner(
                    "Kein Internet - Firmware-Cache nicht aktualisiert. Alte Version wird verwendet."))
            else:
                self.after(0, lambda: self._show_inet_banner(
                    "Kein Internet und kein Firmware-Cache! Bitte Hub mit Internet starten."))

    def _show_inet_banner(self, text):
        self.dash_inet_label.config(text=text)
        self.dash_inet_banner.config(height=40)
        if not self.dash_inet_banner.winfo_ismapped():
            self.dash_inet_banner.pack(fill="x", pady=(8, 0))

    # ---- Tabs ----
    def _build_tabs(self):
        style = ttk.Style()
        style.theme_use("default")
        style.configure("TNotebook", background=COL_BG, borderwidth=0)
        style.configure("TNotebook.Tab", font=("Segoe UI", 10, "bold"),
                        padding=[14, 6], background="#E0E0E0", foreground=COL_TEXT)
        style.map("TNotebook.Tab",
                  background=[("selected", COL_PRIMARY)],
                  foreground=[("selected", COL_WHITE)])

        self.notebook = ttk.Notebook(self)
        self.notebook.pack(fill="both", expand=True, padx=12, pady=(8, 12))

        self.tab_dash = tk.Frame(self.notebook, bg=COL_BG)
        self.tab_pi   = tk.Frame(self.notebook, bg=COL_BG)
        self.tab_rec  = tk.Frame(self.notebook, bg=COL_BG)
        self.tab_tool = tk.Frame(self.notebook, bg=COL_BG)
        self.tab_supa = tk.Frame(self.notebook, bg=COL_BG)
        self.tab_docs = tk.Frame(self.notebook, bg=COL_BG)

        self.notebook.add(self.tab_dash, text="  Dashboard  ")
        self.notebook.add(self.tab_pi,   text="  Pi-Steuerung  ")
        self.notebook.add(self.tab_rec,  text="  Recording  ")
        self.notebook.add(self.tab_tool, text="  Tools  ")
        self.notebook.add(self.tab_supa, text="  Supabase  ")
        self.notebook.add(self.tab_docs, text="  Doku  ")

        self._build_tab_dashboard()
        self._build_tab_pi_control()
        self._build_tab_recording()
        self._build_tab_tools()
        self._build_tab_supabase()
        self._build_tab_docs()

    # ---- Helpers ----
    def _card(self, parent, **kw):
        f = tk.Frame(parent, bg=COL_CARD, highlightbackground=COL_CARD_BDR,
                     highlightthickness=1, bd=0, **kw)
        return f

    def _section(self, parent, text, top=0):
        tk.Label(parent, text=text, font=("Segoe UI", 8, "bold"),
                 bg=COL_BG, fg=COL_PRIMARY).pack(fill="x", pady=(top, 4), anchor="w")

    def _btn(self, parent, text, cmd, color=None, **kw):
        bg = color or COL_WHITE
        fg = COL_WHITE if color else COL_TEXT
        abg = COL_PRIMARY_D if color else "#FFF3E0"
        return tk.Button(parent, text=text, font=("Segoe UI", 10), bg=bg, fg=fg,
                         activebackground=abg, activeforeground=fg,
                         borderwidth=1, relief="solid", padx=12, pady=5,
                         cursor="hand2", command=cmd, **kw)

    def _indicator(self, parent, var_name):
        canvas = tk.Canvas(parent, width=16, height=16, bg=COL_CARD,
                           highlightthickness=0)
        oid = canvas.create_oval(2, 2, 14, 14, fill="#BDBDBD", outline="")
        setattr(self, var_name, (canvas, oid))
        return canvas

    def _set_indicator(self, var_name, color):
        canvas, oid = getattr(self, var_name)
        canvas.itemconfig(oid, fill=color)

    # ============================================================
    # Tab 1: Dashboard
    # ============================================================
    def _build_tab_dashboard(self):
        p = tk.Frame(self.tab_dash, bg=COL_BG, padx=16, pady=12)
        p.pack(fill="both", expand=True)

        top_bar = tk.Frame(p, bg=COL_BG)
        top_bar.pack(fill="x", pady=(0, 6))
        tk.Label(top_bar, text="SYSTEM-STATUS", font=("Segoe UI", 8, "bold"),
                 bg=COL_BG, fg=COL_PRIMARY).pack(side="left")
        self._btn(top_bar, "Aktualisieren", self._refresh_dashboard,
                  color=COL_PRIMARY).pack(side="right")

        card = self._card(p)
        card.pack(fill="x")

        rows_data = [
            ("Pi erreichbar:", "dash_pi"),
            ("Sensor:", "dash_sensor"),
            ("Aufnahme:", "dash_rec"),
        ]
        for i, (label, ind_name) in enumerate(rows_data):
            row_bg = "#FFF8F0" if i % 2 == 0 else COL_CARD
            row = tk.Frame(card, bg=row_bg)
            row.pack(fill="x")
            self._indicator(row, ind_name)
            getattr(self, ind_name)[0].pack(side="left", padx=(12, 6), pady=6)
            tk.Label(row, text=label, font=("Segoe UI", 10),
                     bg=row_bg, fg=COL_TEXT_SEC, width=18, anchor="w").pack(side="left")
            val_label = tk.Label(row, text="--", font=("Segoe UI", 10, "bold"),
                                 bg=row_bg, fg=COL_TEXT, anchor="w")
            val_label.pack(side="left", fill="x", expand=True)
            setattr(self, f"{ind_name}_val", val_label)

        self.dash_inet_banner = tk.Frame(p, bg=COL_ERROR, height=0)
        self.dash_inet_banner.pack_propagate(False)
        ib = tk.Frame(self.dash_inet_banner, bg=COL_ERROR)
        ib.pack(fill="both", expand=True, padx=12)
        self.dash_inet_label = tk.Label(ib, text="", font=("Segoe UI", 10, "bold"),
                                        bg=COL_ERROR, fg="#FFFFFF", anchor="w")
        self.dash_inet_label.pack(side="left", fill="x", expand=True)

        self.dash_fw_banner = tk.Frame(p, bg=COL_WARN, height=0)
        self.dash_fw_banner.pack_propagate(False)
        binner = tk.Frame(self.dash_fw_banner, bg=COL_WARN)
        binner.pack(fill="both", expand=True, padx=12)
        self.dash_fw_label = tk.Label(binner, text="", font=("Segoe UI", 10, "bold"),
                                      bg=COL_WARN, fg="#FFFFFF", anchor="w")
        self.dash_fw_label.pack(side="left", fill="x", expand=True)
        self.dash_fw_btn = tk.Button(binner, text="Zur Pi-Steuerung",
                                     font=("Segoe UI", 9, "bold"),
                                     bg="#E65100", fg="#FFFFFF", bd=0,
                                     activebackground="#BF360C",
                                     activeforeground="#FFFFFF",
                                     cursor="hand2",
                                     command=lambda: self.notebook.select(self.tab_pi))
        self.dash_fw_btn.pack(side="right", padx=(8, 4), pady=4)

        self._section(p, "LETZTE MESSWERTE", top=14)
        card2 = self._card(p)
        card2.pack(fill="x")
        mf = tk.Frame(card2, bg=COL_CARD)
        mf.pack(fill="x", padx=16, pady=12)

        for col_idx, (lbl, attr) in enumerate([("P1 [bar]", "dash_p1"), ("TOB1 [\u00b0C]", "dash_tob1")]):
            cf = tk.Frame(mf, bg=COL_CARD)
            cf.pack(side="left", expand=True, fill="x")
            tk.Label(cf, text=lbl, font=("Segoe UI", 9), bg=COL_CARD,
                     fg=COL_TEXT_SEC).pack()
            val = tk.Label(cf, text="--", font=("Segoe UI", 28, "bold"),
                           bg=COL_CARD, fg=COL_PRIMARY)
            val.pack()
            setattr(self, attr, val)

        self._section(p, "DETAILS", top=14)
        card3 = self._card(p)
        card3.pack(fill="x")
        self.dash_details = tk.Label(card3, text="Warte auf Verbindung...",
                                     font=("Consolas", 9), bg=COL_CARD, fg=COL_TEXT_SEC,
                                     anchor="nw", justify="left")
        self.dash_details.pack(fill="x", padx=12, pady=10)

    def _refresh_dashboard(self):
        def _do():
            health = _api_get("/health")
            status = _api_get("/recording/status")
            if health and not getattr(self, '_time_synced', False):
                ts = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
                sync = _api_post("/time/sync", {"timestamp": ts})
                if sync and sync.get("status") == "synced":
                    self._time_synced = True
            self.after(0, lambda: self._update_dashboard(health, status))
        threading.Thread(target=_do, daemon=True).start()

    def _update_dashboard(self, health, status):
        if health is None:
            self._set_indicator("dash_pi", COL_ERROR)
            self.dash_pi_val.config(text="Nicht erreichbar")
            self._set_indicator("dash_sensor", "#BDBDBD")
            self.dash_sensor_val.config(text="--")
            self._set_indicator("dash_rec", "#BDBDBD")
            self.dash_rec_val.config(text="--")
            self.dash_p1.config(text="--")
            self.dash_tob1.config(text="--")
            self.dash_details.config(text=f"Pi nicht erreichbar unter {PI_BASE}\n"
                                          f"WiFi '{WIFI_SSID}' verbunden?")
            self._hide_fw_banner()
            return

        self._set_indicator("dash_pi", COL_SUCCESS)
        self.dash_pi_val.config(text=f"{PI_IP}:{PI_PORT}")

        sensor_ok = health.get("sensor_connected", False)
        self._set_indicator("dash_sensor", COL_SUCCESS if sensor_ok else COL_WARN)
        sn = health.get("serial_number", "")
        port = health.get("sensor_port", "")
        self.dash_sensor_val.config(
            text=f"SN {sn} ({port})" if sensor_ok else "Nicht verbunden")

        if status and status.get("recording"):
            self._set_indicator("dash_rec", COL_ACCENT)
            name = status.get("name", "")
            samples = status.get("sample_count", 0)
            elapsed = status.get("elapsed_seconds", 0)
            mins = elapsed // 60
            self.dash_rec_val.config(text=f"{name} - {samples} Samples ({mins} min)")
        else:
            self._set_indicator("dash_rec", "#BDBDBD")
            self.dash_rec_val.config(text="Keine aktive Aufnahme")

        p1 = (status or {}).get("last_p1") or health.get("last_p1")
        tob1 = (status or {}).get("last_tob1") or health.get("last_tob1")
        self.dash_p1.config(text=f"{p1:.4f}" if p1 is not None else "--")
        self.dash_tob1.config(text=f"{tob1:.2f}" if tob1 is not None else "--")

        pi_ver = health.get("version", "")
        if pi_ver:
            threading.Thread(target=self._auto_fw_check, args=(pi_ver,), daemon=True).start()

        details = []
        details.append(f"Pi-Version:    {pi_ver or 'unbekannt'}")
        details.append(f"Timestamp:     {health.get('timestamp', '--')}")
        details.append(f"Sensor Port:   {health.get('sensor_port', '--')}")
        details.append(f"Serial Number: {health.get('serial_number', '--')}")
        details.append(f"Uhr sync:      {'Ja' if getattr(self, '_time_synced', False) else 'Nein'}")
        if status and status.get("recording"):
            details.append(f"Recording:     {status.get('name')}")
            details.append(f"Medium:        {status.get('medium')}")
            details.append(f"Intervall:     {status.get('interval_s')}s")
            details.append(f"PN:            {status.get('pn')}")
        self.dash_details.config(text="\n".join(details))

    # ============================================================
    # Tab 2: Pi-Steuerung
    # ============================================================
    def _build_tab_pi_control(self):
        p = tk.Frame(self.tab_pi, bg=COL_BG, padx=16, pady=12)
        p.pack(fill="both", expand=True)

        self._section(p, "AKTIONEN")
        card = self._card(p)
        card.pack(fill="x")
        bf = tk.Frame(card, bg=COL_CARD)
        bf.pack(fill="x", padx=12, pady=12)

        actions = [
            ("SSH Terminal oeffnen", self._ssh_open, COL_PRIMARY),
            ("Service neustarten", self._ssh_restart_service, COL_ACCENT),
            ("Pi rebooten", self._pi_reboot, COL_ERROR),
            ("WiFi aus (120s)", self._pi_wifi_off, COL_WARN),
        ]
        for i, (text, cmd, color) in enumerate(actions):
            btn = self._btn(bf, text, cmd, color=color)
            btn.pack(fill="x", pady=3)

        self._section(p, "FIRMWARE-UPDATE", top=14)
        card_fw = self._card(p)
        card_fw.pack(fill="x")
        fw_f = tk.Frame(card_fw, bg=COL_CARD)
        fw_f.pack(fill="x", padx=12, pady=10)

        self.fw_status = tk.Label(fw_f, text="", font=("Segoe UI", 9),
                                  bg=COL_CARD, fg=COL_TEXT_SEC, anchor="w", justify="left")
        self.fw_status.pack(fill="x")

        fw_btns = tk.Frame(fw_f, bg=COL_CARD)
        fw_btns.pack(fill="x", pady=(6, 0))
        self._btn(fw_btns, "Pi-Firmware pruefen", self._fw_check,
                  color=COL_PRIMARY).pack(side="left")
        self.fw_update_btn = self._btn(fw_btns, "Jetzt updaten", self._fw_apply,
                                       color=COL_SUCCESS)

        self._section(p, "SERVICE-LOGS", top=14)
        card2 = self._card(p)
        card2.pack(fill="both", expand=True)

        log_bar = tk.Frame(card2, bg=COL_CARD)
        log_bar.pack(fill="x", padx=10, pady=(8, 0))
        self._btn(log_bar, "Logs laden", self._load_pi_logs).pack(side="left")
        self._btn(log_bar, "Logs loeschen", lambda: self.pi_log_text.delete("1.0", tk.END)).pack(side="left", padx=6)

        self.pi_log_text = tk.Text(card2, height=10, font=("Consolas", 9),
                                   bg="#1E1E1E", fg="#D4D4D4", insertbackground=COL_WHITE,
                                   borderwidth=0, wrap="word")
        self.pi_log_text.pack(fill="both", expand=True, padx=10, pady=10)

    def _ssh_open(self):
        try:
            subprocess.Popen(
                ["powershell", "-NoExit", "-Command",
                 f"Write-Host '========================================' -ForegroundColor DarkGray; "
                 f"Write-Host '  Passwort: {PI_PASS}' -ForegroundColor Yellow; "
                 f"Write-Host '========================================' -ForegroundColor DarkGray; "
                 f"Write-Host ''; "
                 f"ssh -o StrictHostKeyChecking=no {PI_USER}@{PI_IP}"],
                creationflags=subprocess.CREATE_NEW_CONSOLE)
        except Exception as e:
            messagebox.showerror("Fehler", f"SSH konnte nicht gestartet werden:\n{e}")

    def _ssh_restart_service(self):
        if not messagebox.askokcancel("Service neustarten",
                "Prezio-Recorder Service wirklich neustarten?"):
            return
        self.pi_log_text.insert(tk.END, "\n>>> Service wird neugestartet...\n")
        def _do():
            out, err = _ssh_exec("sudo systemctl restart prezio-recorder && echo OK")
            result = out.strip() if out else err
            self.after(0, lambda: self.pi_log_text.insert(tk.END, f"<<< {result}\n"))
        threading.Thread(target=_do, daemon=True).start()

    def _pi_reboot(self):
        if not messagebox.askokcancel("Pi rebooten",
                "Raspberry Pi wirklich neu starten?\n"
                "Der Pi ist danach ca. 60s nicht erreichbar."):
            return
        result = _api_post("/reboot")
        if result and result.get("status") == "rebooting":
            messagebox.showinfo("Reboot", "Pi startet neu...")
        else:
            messagebox.showerror("Fehler", f"Reboot fehlgeschlagen:\n{result}")

    def _pi_wifi_off(self):
        if not messagebox.askokcancel("WiFi ausschalten",
                "WiFi wird fuer 120 Sekunden deaktiviert.\n"
                "Danach startet es automatisch neu.\n\n"
                "Die Verbindung zum Pi geht verloren!"):
            return
        result = _api_post("/wifi/off")
        if result and "error" not in result:
            messagebox.showinfo("WiFi", "WiFi wird deaktiviert. Startet in 120s automatisch neu.")
        else:
            messagebox.showerror("Fehler", f"WiFi-off fehlgeschlagen:\n{result}")

    def _load_pi_logs(self):
        self.pi_log_text.insert(tk.END, "\n>>> Lade Logs...\n")
        def _do():
            out, err = _ssh_exec("sudo journalctl -u prezio-recorder -n 80 --no-pager")
            text = out if out else err
            self.after(0, lambda: (
                self.pi_log_text.delete("1.0", tk.END),
                self.pi_log_text.insert("1.0", text),
                self.pi_log_text.see(tk.END)))
        threading.Thread(target=_do, daemon=True).start()

    # ---- Firmware Update ----
    def _fw_check(self):
        """Compare Pi version with cached firmware from GitHub main."""
        self.fw_status.config(text="Pruefe Versionen...", fg=COL_TEXT_SEC)
        self.fw_update_btn.pack_forget()
        def _do():
            health = _api_get("/health")
            self.after(0, lambda: self._fw_check_result(health))
        threading.Thread(target=_do, daemon=True).start()

    def _fw_check_result(self, health):
        if health is None:
            self.fw_status.config(
                text="Pi nicht erreichbar - mit WiFi 'Prezio-Recorder' verbinden.",
                fg=COL_ERROR)
            return
        pi_ver = health.get("version", "unbekannt")
        cached_ver = _get_cached_firmware_version()

        if cached_ver is None:
            self.fw_status.config(
                text=f"Pi-Version: {pi_ver}\n"
                     f"Kein Cache vorhanden. Hub mit Internet starten.",
                fg=COL_WARN)
            return

        pi_tuple = _parse_version(pi_ver)
        cached_tuple = _parse_version(cached_ver)

        if cached_tuple > pi_tuple:
            self.fw_status.config(
                text=f"Update verfuegbar!\n"
                     f"Pi: v{pi_ver}  ->  Cache: v{cached_ver}",
                fg=COL_SUCCESS)
            self.fw_update_btn.pack(side="left", padx=(8, 0))
        else:
            self.fw_status.config(
                text=f"Pi ist aktuell (v{pi_ver}).",
                fg=COL_TEXT_SEC)

    def _fw_apply(self):
        cached = os.path.join(FIRMWARE_CACHE, "pi_recorder.py")
        if not os.path.exists(cached):
            messagebox.showerror("Fehler",
                "Keine gecachte Firmware vorhanden.\n"
                "Bitte PrezioHub einmal mit Internet starten.")
            return
        if not messagebox.askokcancel("Pi-Firmware updaten",
                "Die neue pi_recorder.py wird auf den Pi hochgeladen\n"
                "und der Service wird neugestartet.\n\nFortfahren?"):
            return
        self.fw_status.config(text="Lade Firmware auf Pi...", fg=COL_TEXT_SEC)
        self.fw_update_btn.pack_forget()
        def _do():
            result = self._fw_upload_cached()
            self.after(0, lambda: self._fw_apply_result(result))
        threading.Thread(target=_do, daemon=True).start()

    def _fw_upload_cached(self):
        """Upload cached pi_recorder.py to Pi via SFTP and restart service."""
        local_file = os.path.join(FIRMWARE_CACHE, "pi_recorder.py")
        remote_path = "/home/pi/prezio-v2/pi_recorder/pi_recorder.py"
        ok, msg = _sftp_upload(local_file, remote_path)
        if not ok:
            return False, f"Upload fehlgeschlagen: {msg}"
        out, err = _ssh_exec("sudo systemctl restart prezio-recorder")
        if err and "fehlgeschlagen" in err.lower():
            return False, f"Service-Restart fehlgeschlagen: {err}"
        ver = _get_cached_firmware_version() or "?"
        return True, f"Update auf v{ver} erfolgreich!"

    def _fw_apply_result(self, result):
        ok, msg = result
        if ok:
            self.fw_status.config(text=msg, fg=COL_SUCCESS)
        else:
            self.fw_status.config(text=msg, fg=COL_ERROR)
            self.fw_update_btn.pack(side="left", padx=(8, 0))

    def _auto_fw_check(self, pi_ver):
        """Auto-check: compare Pi version with cached firmware version."""
        cached_ver = _get_cached_firmware_version()
        if not cached_ver:
            self.after(0, self._hide_fw_banner)
            return
        pi_tuple = _parse_version(pi_ver)
        cached_tuple = _parse_version(cached_ver)
        if cached_tuple > pi_tuple:
            def _show():
                self.fw_status.config(
                    text=f"Pi-Firmware veraltet! Pi: v{pi_ver} -> Cache: v{cached_ver}\n"
                         f"Wechsle zu 'Pi-Steuerung' um zu updaten.",
                    fg=COL_WARN)
                self.fw_update_btn.pack(side="left", padx=(8, 0))
                self._show_fw_banner(pi_ver, cached_ver)
            self.after(0, _show)
        else:
            self.after(0, self._hide_fw_banner)

    def _show_fw_banner(self, pi_ver, cached_ver):
        self.dash_fw_label.config(
            text=f"UPDATE FAELLIG:  Pi v{pi_ver}  \u2192  v{cached_ver}")
        self.dash_fw_banner.config(height=40)
        if not self.dash_fw_banner.winfo_ismapped():
            self.dash_fw_banner.pack(fill="x", pady=(8, 0))

    def _hide_fw_banner(self):
        if self.dash_fw_banner.winfo_ismapped():
            self.dash_fw_banner.pack_forget()

    # ============================================================
    # Tab 3: Recording & Dateien
    # ============================================================
    def _build_tab_recording(self):
        p = tk.Frame(self.tab_rec, bg=COL_BG, padx=16, pady=12)
        p.pack(fill="both", expand=True)

        top = tk.Frame(p, bg=COL_BG)
        top.pack(fill="x")

        # Left: Recording controls
        left = tk.Frame(top, bg=COL_BG)
        left.pack(side="left", fill="both", expand=True, padx=(0, 8))

        self._section(left, "AUFNAHME STEUERN")
        card = self._card(left)
        card.pack(fill="x")
        form = tk.Frame(card, bg=COL_CARD)
        form.pack(fill="x", padx=12, pady=10)

        fields = [("Name:", "rec_name"), ("PN:", "rec_pn"), ("Medium:", "rec_medium"),
                  ("Intervall (s):", "rec_interval")]
        defaults = ["", "25", "air", "10"]
        for i, ((lbl, attr), default) in enumerate(zip(fields, defaults)):
            row = tk.Frame(form, bg=COL_CARD)
            row.pack(fill="x", pady=2)
            tk.Label(row, text=lbl, font=("Segoe UI", 9), bg=COL_CARD,
                     fg=COL_TEXT_SEC, width=12, anchor="w").pack(side="left")
            if attr == "rec_medium":
                var = tk.StringVar(value=default)
                cb = ttk.Combobox(row, textvariable=var, values=["air", "water"],
                                  state="readonly", width=14)
                cb.pack(side="left")
                setattr(self, attr, var)
            else:
                entry = tk.Entry(row, font=("Segoe UI", 10), width=16)
                entry.insert(0, default)
                entry.pack(side="left")
                setattr(self, attr, entry)

        btn_row = tk.Frame(card, bg=COL_CARD)
        btn_row.pack(fill="x", padx=12, pady=(4, 10))
        self._btn(btn_row, "Aufnahme starten", self._rec_start, color=COL_SUCCESS).pack(side="left")
        self._btn(btn_row, "Aufnahme stoppen", self._rec_stop, color=COL_ERROR).pack(side="left", padx=6)

        # Right: Live status
        right_f = tk.Frame(top, bg=COL_BG, width=200)
        right_f.pack(side="right", fill="y")

        self._section(right_f, "LIVE-STATUS")
        card_r = self._card(right_f)
        card_r.pack(fill="x")
        self.rec_status_label = tk.Label(card_r, text="--", font=("Segoe UI", 10),
                                         bg=COL_CARD, fg=COL_TEXT_SEC,
                                         wraplength=180, justify="left", anchor="nw")
        self.rec_status_label.pack(fill="x", padx=10, pady=10)

        # Bottom: Files
        self._section(p, "DATEIEN AUF DEM PI", top=14)
        card_f = self._card(p)
        card_f.pack(fill="both", expand=True)

        file_bar = tk.Frame(card_f, bg=COL_CARD)
        file_bar.pack(fill="x", padx=10, pady=(8, 0))
        self._btn(file_bar, "Aktualisieren", self._files_refresh).pack(side="left")
        self._btn(file_bar, "Herunterladen", self._files_download).pack(side="left", padx=4)
        self._btn(file_bar, "Loeschen", self._files_delete).pack(side="left")

        cols = ("filename", "size", "modified")
        self.files_tree = ttk.Treeview(card_f, columns=cols, show="headings", height=6)
        self.files_tree.heading("filename", text="Dateiname")
        self.files_tree.heading("size", text="Groesse")
        self.files_tree.heading("modified", text="Geaendert")
        self.files_tree.column("filename", width=280)
        self.files_tree.column("size", width=80)
        self.files_tree.column("modified", width=160)
        self.files_tree.pack(fill="both", expand=True, padx=10, pady=10)

    def _rec_start(self):
        name = self.rec_name.get().strip()
        if not name:
            messagebox.showwarning("Name fehlt", "Bitte einen Namen eingeben.")
            return
        body = {
            "name": name,
            "pn": int(self.rec_pn.get() or 25),
            "medium": self.rec_medium.get(),
            "interval_s": float(self.rec_interval.get() or 10),
        }
        def _do():
            result = _api_post("/recording/start", body)
            self.after(0, lambda: self._rec_start_result(result))
        threading.Thread(target=_do, daemon=True).start()

    def _rec_start_result(self, result):
        if result and result.get("status") == "started":
            messagebox.showinfo("Aufnahme", f"Aufnahme gestartet: {result.get('name')}")
        else:
            messagebox.showerror("Fehler", f"Start fehlgeschlagen:\n{result}")

    def _rec_stop(self):
        def _do():
            result = _api_post("/recording/stop")
            self.after(0, lambda: self._rec_stop_result(result))
        threading.Thread(target=_do, daemon=True).start()

    def _rec_stop_result(self, result):
        if result and result.get("status") == "stopped":
            messagebox.showinfo("Aufnahme",
                f"Aufnahme gestoppt.\n"
                f"Datei: {result.get('filename')}\n"
                f"Samples: {result.get('samples')}")
            self._files_refresh()
        else:
            messagebox.showerror("Fehler", f"Stopp fehlgeschlagen:\n{result}")

    def _refresh_recording_status(self):
        def _do():
            status = _api_get("/recording/status")
            self.after(0, lambda: self._update_rec_status(status))
        threading.Thread(target=_do, daemon=True).start()

    def _update_rec_status(self, status):
        if status is None:
            self.rec_status_label.config(text="Pi nicht erreichbar", fg=COL_ERROR)
            return
        if status.get("recording"):
            p1 = status.get("last_p1")
            tob1 = status.get("last_tob1")
            lines = [
                "Aufnahme aktiv",
                f"Name: {status.get('name')}",
                f"Samples: {status.get('sample_count')}",
            ]
            if p1 is not None:
                lines.append(f"P1: {p1:.4f} bar")
            if tob1 is not None:
                lines.append(f"TOB1: {tob1:.2f} \u00b0C")
            self.rec_status_label.config(text="\n".join(lines), fg=COL_SUCCESS)
        else:
            self.rec_status_label.config(text="Keine aktive Aufnahme", fg=COL_TEXT_SEC)

    def _files_refresh(self):
        def _do():
            files = _api_get("/files")
            self.after(0, lambda: self._update_files(files))
        threading.Thread(target=_do, daemon=True).start()

    def _update_files(self, files):
        self.files_tree.delete(*self.files_tree.get_children())
        if not files:
            return
        for f in files:
            size_kb = f.get("size", 0) / 1024
            self.files_tree.insert("", tk.END, values=(
                f.get("filename", ""),
                f"{size_kb:.1f} KB",
                f.get("modified", ""),
            ))

    def _files_download(self):
        sel = self.files_tree.selection()
        if not sel:
            messagebox.showwarning("Auswahl", "Bitte eine Datei auswaehlen.")
            return
        filename = self.files_tree.item(sel[0])["values"][0]
        dest = filedialog.asksaveasfilename(defaultextension=".csv",
            initialfile=filename, filetypes=[("CSV", "*.csv"), ("Alle", "*.*")])
        if not dest:
            return
        def _do():
            content = _api_get_text(f"/files/{filename}")
            if content:
                with open(dest, "w", encoding="utf-8") as f:
                    f.write(content)
                self.after(0, lambda: messagebox.showinfo("Gespeichert", f"Datei gespeichert:\n{dest}"))
            else:
                self.after(0, lambda: messagebox.showerror("Fehler", "Download fehlgeschlagen."))
        threading.Thread(target=_do, daemon=True).start()

    def _files_delete(self):
        sel = self.files_tree.selection()
        if not sel:
            messagebox.showwarning("Auswahl", "Bitte eine Datei auswaehlen.")
            return
        filename = self.files_tree.item(sel[0])["values"][0]
        if not messagebox.askokcancel("Loeschen", f"Datei '{filename}' wirklich loeschen?"):
            return
        def _do():
            result = _api_delete(f"/files/{filename}")
            self.after(0, lambda: (
                messagebox.showinfo("Geloescht", f"'{filename}' geloescht.")
                if result and result.get("status") == "deleted"
                else messagebox.showerror("Fehler", f"Loeschen fehlgeschlagen:\n{result}"),
                self._files_refresh()))
        threading.Thread(target=_do, daemon=True).start()

    # ============================================================
    # Tab 4: Tools
    # ============================================================
    def _build_tab_tools(self):
        p = tk.Frame(self.tab_tool, bg=COL_BG, padx=16, pady=12)
        p.pack(fill="both", expand=True)

        self._section(p, "PROGRAMME STARTEN")

        tools = [
            ("PrezioImager",  "SD-Karten Flash Tool",         "imager",  self._tool_imager),
            ("PC Recorder",   "Windows-Recorder mit GUI",     "pc_rec",  self._tool_pc_recorder),
            ("Dummy Server",  "Mock-Server fuer Entwicklung", "dummy",   self._tool_dummy_server),
        ]

        for name, desc, key, cmd in tools:
            card = self._card(p)
            card.pack(fill="x", pady=4)
            row = tk.Frame(card, bg=COL_CARD)
            row.pack(fill="x", padx=14, pady=10)

            info = tk.Frame(row, bg=COL_CARD)
            info.pack(side="left", fill="x", expand=True)
            tk.Label(info, text=name, font=("Segoe UI", 11, "bold"),
                     bg=COL_CARD, fg=COL_TEXT).pack(anchor="w")
            tk.Label(info, text=desc, font=("Segoe UI", 9),
                     bg=COL_CARD, fg=COL_TEXT_SEC).pack(anchor="w")

            status_label = tk.Label(row, text="", font=("Segoe UI", 9),
                                    bg=COL_CARD, fg=COL_TEXT_SEC)
            status_label.pack(side="right", padx=(0, 8))
            setattr(self, f"tool_{key}_status", status_label)

            self._btn(row, "Starten", cmd, color=COL_PRIMARY).pack(side="right")

    def _find_tool(self, *candidates):
        """Search for a tool: first in BASE_DIR (installed), then in PROJECT_ROOT (dev)."""
        for name in candidates:
            for base in [BASE_DIR, PROJECT_ROOT]:
                full = os.path.join(base, name)
                if os.path.exists(full):
                    return full
        return None

    def _launch_exe(self, name, *search_names, status_attr=None, needs_admin=False):
        path = self._find_tool(*search_names)
        if path:
            if needs_admin:
                os.startfile(path)
            else:
                subprocess.Popen([path], cwd=os.path.dirname(path))
            if status_attr:
                getattr(self, status_attr).config(text="Gestartet", fg=COL_SUCCESS)
        else:
            messagebox.showerror("Nicht gefunden",
                f"{name} nicht gefunden.\n"
                f"Gesucht in:\n  {BASE_DIR}\n  {PROJECT_ROOT}")

    def _tool_imager(self):
        self._launch_exe("PrezioImager",
            "PrezioImager.exe",
            "pi_recorder/dist/PrezioImager.exe",
            "pi_recorder/PrezioImager.exe",
            status_attr="tool_imager_status",
            needs_admin=True)

    def _tool_pc_recorder(self):
        self._launch_exe("PrezioRecorder",
            "PrezioRecorder.exe",
            "pc_recorder/PrezioRecorder.exe",
            status_attr="tool_pc_rec_status")

    def _tool_dummy_server(self):
        path = self._find_tool(
            "PrezioDummy.exe",
            "dummy_server/PrezioDummy.exe",
        )
        if path:
            subprocess.Popen([path], cwd=os.path.dirname(path),
                             creationflags=subprocess.CREATE_NEW_CONSOLE)
            self.tool_dummy_status.config(text="Gestartet", fg=COL_SUCCESS)
        else:
            messagebox.showerror("Nicht gefunden",
                f"Dummy Server nicht gefunden.\n"
                f"Gesucht in:\n  {BASE_DIR}\n  {PROJECT_ROOT}")

    # ============================================================
    # Tab 5: Supabase
    # ============================================================
    def _build_tab_supabase(self):
        p = tk.Frame(self.tab_supa, bg=COL_BG, padx=16, pady=12)
        p.pack(fill="both", expand=True)

        self._section(p, "SUPABASE-CONFIG")
        card_cfg = self._card(p)
        card_cfg.pack(fill="x")
        cfg_f = tk.Frame(card_cfg, bg=COL_CARD)
        cfg_f.pack(fill="x", padx=12, pady=8)

        for lbl, val in [("URL:", SUPABASE_URL), ("Bucket:", SUPABASE_BUCKET),
                         ("Key:", SUPABASE_KEY[:20] + "...")]:
            row = tk.Frame(cfg_f, bg=COL_CARD)
            row.pack(fill="x")
            tk.Label(row, text=lbl, font=("Segoe UI", 9, "bold"), bg=COL_CARD,
                     fg=COL_TEXT_SEC, width=8, anchor="w").pack(side="left")
            tk.Label(row, text=val, font=("Segoe UI", 9), bg=COL_CARD,
                     fg=COL_TEXT, anchor="w").pack(side="left")

        top_btns = tk.Frame(p, bg=COL_BG)
        top_btns.pack(fill="x", pady=(8, 0))
        self._btn(top_btns, "Dashboard oeffnen",
                  lambda: os.startfile(SUPABASE_DASHBOARD)).pack(side="left")

        # --- Storage section ---
        self._section(p, "PROTOKOLL-STORAGE", top=10)
        stor_bar = tk.Frame(p, bg=COL_BG)
        stor_bar.pack(fill="x", pady=(4, 0))
        self._btn(stor_bar, "Ordner laden", self._supa_storage_load,
                  color=COL_PRIMARY).pack(side="left")
        self._btn(stor_bar, "Datei herunterladen", self._supa_storage_download_file).pack(
            side="left", padx=4)
        self._btn(stor_bar, "Als ZIP herunterladen", self._supa_storage_download_zip).pack(
            side="left", padx=4)

        self._supa_folder_data = {}

        stor_cols = ("name", "size", "date")
        self.supa_stor_tree = ttk.Treeview(p, columns=stor_cols, show="tree headings",
                                           height=10)
        self.supa_stor_tree.heading("#0", text="")
        self.supa_stor_tree.heading("name", text="Name")
        self.supa_stor_tree.heading("size", text="Groesse")
        self.supa_stor_tree.heading("date", text="Datum")
        self.supa_stor_tree.column("#0", width=30)
        self.supa_stor_tree.column("name", width=320)
        self.supa_stor_tree.column("size", width=80)
        self.supa_stor_tree.column("date", width=160)
        self.supa_stor_tree.pack(fill="both", expand=True, pady=6)
        self.supa_stor_tree.bind("<<TreeviewOpen>>", self._supa_storage_on_expand)

        self.supa_stor_status = tk.Label(p, text="", font=("Segoe UI", 9),
                                         bg=COL_BG, fg=COL_TEXT_SEC)
        self.supa_stor_status.pack(anchor="w")

    # --- Storage methods ---
    def _supa_storage_load(self):
        self.supa_stor_status.config(text="Lade Ordner...", fg=COL_TEXT_SEC)
        def _do():
            items = _supabase_storage_list(prefix="")
            self.after(0, lambda: self._supa_storage_fill_folders(items))
        threading.Thread(target=_do, daemon=True).start()

    def _supa_storage_fill_folders(self, items):
        self.supa_stor_tree.delete(*self.supa_stor_tree.get_children())
        self._supa_folder_data.clear()
        if items is None:
            self.supa_stor_status.config(text="Storage: Verbindung fehlgeschlagen", fg=COL_ERROR)
            return
        folders = [i for i in items if i.get("id") is None]
        files = [i for i in items if i.get("id") is not None]
        folders.sort(key=lambda x: x.get("name", ""), reverse=True)
        count = 0
        for folder in folders:
            name = folder.get("name", "")
            node = self.supa_stor_tree.insert("", tk.END, text="\U0001f4c1",
                                              values=(name, "", ""),
                                              open=False)
            self._supa_folder_data[node] = {"type": "folder", "path": name}
            self.supa_stor_tree.insert(node, tk.END, text="", values=("Laden...", "", ""))
            count += 1
        for f in files:
            meta = f.get("metadata") or {}
            size = meta.get("size", 0)
            size_str = f"{size / 1024:.1f} KB" if size > 0 else ""
            date_str = (f.get("created_at") or "")[:19].replace("T", " ")
            node = self.supa_stor_tree.insert("", tk.END, text="\U0001f4c4",
                                              values=(f.get("name", ""), size_str, date_str))
            self._supa_folder_data[node] = {"type": "file", "path": f.get("name", "")}
        self.supa_stor_status.config(
            text=f"Storage: {count} Ordner, {len(files)} Dateien geladen", fg=COL_TEXT_SEC)

    def _supa_storage_on_expand(self, event):
        node = self.supa_stor_tree.focus()
        info = self._supa_folder_data.get(node)
        if not info or info["type"] != "folder":
            return
        children = self.supa_stor_tree.get_children(node)
        if len(children) == 1:
            first_vals = self.supa_stor_tree.item(children[0])["values"]
            if first_vals and first_vals[0] == "Laden...":
                folder_path = info["path"]
                self.supa_stor_tree.delete(children[0])
                self.supa_stor_status.config(text=f"Lade {folder_path}...", fg=COL_TEXT_SEC)
                def _do():
                    items = _supabase_storage_list(prefix=f"{folder_path}/")
                    self.after(0, lambda: self._supa_storage_fill_files(node, folder_path, items))
                threading.Thread(target=_do, daemon=True).start()

    def _supa_storage_fill_files(self, parent_node, folder_path, items):
        if items is None:
            self.supa_stor_tree.insert(parent_node, tk.END, text="",
                                       values=("Fehler beim Laden", "", ""))
            return
        files = [i for i in items if i.get("id") is not None]
        files.sort(key=lambda x: x.get("name", ""))
        for f in files:
            meta = f.get("metadata") or {}
            size = meta.get("size", 0)
            size_str = f"{size / 1024:.1f} KB" if size > 0 else ""
            date_str = (f.get("created_at") or "")[:19].replace("T", " ")
            fname = f.get("name", "")
            child = self.supa_stor_tree.insert(parent_node, tk.END, text="\U0001f4c4",
                                               values=(fname, size_str, date_str))
            self._supa_folder_data[child] = {
                "type": "file",
                "path": f"{folder_path}/{fname}",
            }
        if not files:
            self.supa_stor_tree.insert(parent_node, tk.END, text="",
                                       values=("(leer)", "", ""))
        self.supa_stor_status.config(
            text=f"{folder_path}: {len(files)} Dateien", fg=COL_TEXT_SEC)

    def _supa_storage_download_file(self):
        sel = self.supa_stor_tree.selection()
        if not sel:
            messagebox.showwarning("Auswahl", "Bitte eine Datei im Storage auswaehlen.")
            return
        info = self._supa_folder_data.get(sel[0])
        if not info or info["type"] != "file":
            messagebox.showwarning("Auswahl", "Bitte eine Datei auswaehlen (kein Ordner).")
            return
        path = info["path"]
        fname = os.path.basename(path)
        dest = filedialog.asksaveasfilename(initialfile=fname,
            filetypes=[("Alle Dateien", "*.*"), ("PDF", "*.pdf"), ("CSV", "*.csv")])
        if not dest:
            return
        self.supa_stor_status.config(text=f"Lade {fname}...", fg=COL_TEXT_SEC)
        def _do():
            data = _supabase_storage_download(path)
            if data:
                with open(dest, "wb") as f:
                    f.write(data)
                self.after(0, lambda: (
                    self.supa_stor_status.config(text=f"Gespeichert: {dest}", fg=COL_SUCCESS),
                    messagebox.showinfo("Gespeichert", f"Datei gespeichert:\n{dest}")))
            else:
                self.after(0, lambda: (
                    self.supa_stor_status.config(text="Download fehlgeschlagen", fg=COL_ERROR),
                    messagebox.showerror("Fehler", "Download fehlgeschlagen.")))
        threading.Thread(target=_do, daemon=True).start()

    def _supa_storage_download_zip(self):
        sel = self.supa_stor_tree.selection()
        if not sel:
            messagebox.showwarning("Auswahl", "Bitte einen Ordner im Storage auswaehlen.")
            return
        info = self._supa_folder_data.get(sel[0])
        if not info or info["type"] != "folder":
            messagebox.showwarning("Auswahl", "Bitte einen Ordner auswaehlen (keine Datei).")
            return
        folder_name = info["path"]
        dest = filedialog.asksaveasfilename(initialfile=f"{folder_name}.zip",
            filetypes=[("ZIP-Archiv", "*.zip")])
        if not dest:
            return
        self.supa_stor_status.config(text=f"Lade Ordner {folder_name} als ZIP...", fg=COL_TEXT_SEC)
        def _do():
            items = _supabase_storage_list(prefix=f"{folder_name}/")
            if items is None:
                self.after(0, lambda: messagebox.showerror("Fehler", "Ordner konnte nicht geladen werden."))
                return
            files = [i for i in items if i.get("id") is not None]
            buf = BytesIO()
            with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
                for f in files:
                    fname = f.get("name", "")
                    fpath = f"{folder_name}/{fname}"
                    self.after(0, lambda fn=fname: self.supa_stor_status.config(
                        text=f"Lade {fn}...", fg=COL_TEXT_SEC))
                    data = _supabase_storage_download(fpath)
                    if data:
                        zf.writestr(fname, data)
            with open(dest, "wb") as f:
                f.write(buf.getvalue())
            self.after(0, lambda: (
                self.supa_stor_status.config(
                    text=f"ZIP gespeichert: {len(files)} Dateien", fg=COL_SUCCESS),
                messagebox.showinfo("Gespeichert",
                    f"ZIP mit {len(files)} Dateien gespeichert:\n{dest}")))
        threading.Thread(target=_do, daemon=True).start()

    # ============================================================
    # Tab 6: Dokumentation
    # ============================================================
    def _build_tab_docs(self):
        p = tk.Frame(self.tab_docs, bg=COL_BG, padx=16, pady=12)
        p.pack(fill="both", expand=True)

        self._section(p, "DOKUMENTATION OEFFNEN")

        docs = [
            ("Projekt-Uebersicht",           "Prezio App: Features, Architektur und CSV-Format",
             "docs/Projekt_Uebersicht.md",   "README.md"),
            ("Technische Dokumentation",     "Vollstaendige Referenz aller Komponenten",
             "docs/Technische_Dokumentation.md", "DOKUMENTATION.md"),
            ("App Store & Google Play",      "Signierung, Codemagic CI/CD und Deployment",
             "docs/App_Store_und_Google_Play.md", "ANLEITUNG_APPSTORE_CONNECT_CODEMAGIC.md"),
            ("Pi Image klonen",              "SD-Karte sichern und auf neue Pis flashen",
             "docs/Pi_Image_klonen.md",      "ANLEITUNG_PI_KLONEN.md"),
            ("Raspberry Pi Ersteinrichtung", "Neuen Prezio Recorder von Grund auf einrichten",
             "docs/Raspberry_Pi_Ersteinrichtung.md", "pi_recorder/howto.txt"),
            ("PC Recorder Handbuch",         "Windows-Tool: KELLER LEO5 auslesen mit GUI",
             "docs/PC_Recorder_Handbuch.md", "pc_recorder/README.md"),
            ("Dummy Server",                 "Mock-Server fuer Tests ohne echten Sensor",
             "docs/Dummy_Server_Anleitung.md", "dummy_server/README.md"),
            ("PrezioHub Anleitung",          "Bedienung des PrezioHub Dashboards",
             "docs/PrezioHub_Anleitung.md",  "PrezioHub_Anleitung.md"),
        ]

        for title, desc, installed_path, dev_path in docs:
            full = None
            for base, rel in [(BASE_DIR, installed_path), (PROJECT_ROOT, dev_path)]:
                candidate = os.path.join(base, rel)
                if os.path.exists(candidate):
                    full = candidate
                    break
            exists = full is not None

            card = self._card(p)
            card.pack(fill="x", pady=3)
            row = tk.Frame(card, bg=COL_CARD)
            row.pack(fill="x", padx=14, pady=8)

            info = tk.Frame(row, bg=COL_CARD)
            info.pack(side="left", fill="x", expand=True)
            tk.Label(info, text=title, font=("Segoe UI", 10, "bold"),
                     bg=COL_CARD, fg=COL_TEXT).pack(anchor="w")
            tk.Label(info, text=desc, font=("Segoe UI", 9),
                     bg=COL_CARD, fg=COL_TEXT_SEC).pack(anchor="w")

            if exists:
                self._btn(row, "Oeffnen",
                          lambda p=full: os.startfile(p)).pack(side="right")
            else:
                tk.Label(row, text="nicht gefunden", font=("Segoe UI", 9),
                         bg=COL_CARD, fg=COL_ERROR).pack(side="right", padx=8)

    # ============================================================
    # Auto-refresh & cleanup
    # ============================================================
    def _schedule_refresh(self):
        if not self._auto_refresh:
            return
        active_tab = self.notebook.index(self.notebook.select())
        if active_tab == 0:
            self._refresh_dashboard()
        elif active_tab == 2:
            self._refresh_recording_status()
        self.after(REFRESH_MS, self._schedule_refresh)

    def _on_close(self):
        self._auto_refresh = False
        self.destroy()


# ============================================================
# Entry point
# ============================================================
if __name__ == "__main__":
    app = PrezioHub()
    app.mainloop()
