#!/usr/bin/env python3
"""
Prezio PC Recorder - KELLER LEO5 Auslesen + HTTP Server fuer App

Dieses Tool:
1. Liest Druckdaten vom KELLER LEO5 ueber COM-Port
2. Zeichnet Messungen auf und speichert sie als CSV
3. Stellt die Daten ueber HTTP bereit (wie der Raspberry Pi)

Die Prezio App kann sich dann mit diesem PC verbinden.
"""

import csv
import http.server
import json
import math
import os
import socket
import struct
import threading
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import unquote
import tkinter as tk
from tkinter import ttk, messagebox

import serial
import serial.tools.list_ports

# ============================================================
# Konfiguration
# ============================================================

DATA_DIR = Path(__file__).parent / "data"
HTTP_PORT = 8080

# ============================================================
# KELLER Protocol
# ============================================================

def crc16_keller(data: bytes) -> bytes:
    crc = 0xFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            odd = crc & 0x0001
            crc >>= 1
            if odd:
                crc ^= 0xA001
    return bytes([(crc >> 8) & 0xFF, crc & 0xFF])


class KellerError(Exception):
    pass


class KellerTimeoutError(KellerError):
    pass


class KellerCRCError(KellerError):
    pass


class KellerProtocolClient:
    def __init__(self) -> None:
        self.ser: serial.Serial | None = None
        self.echo_on = False

    def open(self, port: str, baudrate: int = 9600, timeout: float = 1.0) -> None:
        self.ser = serial.Serial(
            port=port,
            baudrate=baudrate,
            timeout=timeout,
            write_timeout=timeout,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            rtscts=False,
            dsrdtr=False,
            xonxoff=False,
        )
        time.sleep(0.2)
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()
        self.echo_on = self._check_echo()

    def close(self) -> None:
        if self.ser and self.ser.is_open:
            self.ser.close()
        self.ser = None

    @property
    def is_open(self) -> bool:
        return bool(self.ser and self.ser.is_open)

    def _check_echo(self) -> bool:
        if not self.ser:
            return False
        self.ser.reset_input_buffer()
        self.ser.write(b"e")
        self.ser.flush()
        time.sleep(0.25)
        data = self.ser.read_all()
        return data == b"e"

    def _read_exact(self, size: int) -> bytes:
        if not self.ser or not self.ser.is_open:
            raise KellerError("Serielle Verbindung ist nicht offen.")

        buf = bytearray()
        deadline = time.time() + (self.ser.timeout or 1.0) + 0.5

        while len(buf) < size and time.time() < deadline:
            chunk = self.ser.read(size - len(buf))
            if chunk:
                buf.extend(chunk)
            else:
                time.sleep(0.01)

        if len(buf) < size:
            raise KellerTimeoutError(
                f"Timeout beim Lesen. Erwartet: {size} Bytes, erhalten: {len(buf)} Bytes."
            )

        return bytes(buf)

    def _send_receive(self, command_wo_crc: bytes, expected_payload_len: int) -> bytes:
        if not self.ser or not self.ser.is_open:
            raise KellerError("Serielle Verbindung ist nicht offen.")

        frame = command_wo_crc + crc16_keller(command_wo_crc)
        expected_total = 2 + expected_payload_len + 2

        self.ser.reset_input_buffer()
        self.ser.write(frame)
        self.ser.flush()

        if self.echo_on:
            echo = self._read_exact(len(frame))
            if echo != frame:
                raise KellerError(f"Echo passt nicht.")

        answer = self._read_exact(expected_total)

        payload_plus_header = answer[:-2]
        crc_rx = answer[-2:]
        crc_calc = crc16_keller(payload_plus_header)
        if crc_rx != crc_calc:
            raise KellerCRCError(f"CRC falsch.")

        if answer[0] != command_wo_crc[0]:
            raise KellerError(f"Falsche Geraeteadresse in Antwort.")

        if answer[1] > 127:
            error_code = answer[2] if len(answer) > 2 else None
            raise KellerError(f"Geraetefehler: Code={error_code}")

        if answer[1] != command_wo_crc[1]:
            raise KellerError(f"Falscher Funktionscode in Antwort.")

        return answer[2:-2]

    def wakeup(self, address: int = 250) -> bytes:
        return self._send_receive(bytes([address, 48]), 6)

    def read_serial_number(self, address: int) -> int:
        payload = self._send_receive(bytes([address, 69]), 4)
        return int.from_bytes(payload, byteorder="big", signed=False)

    def read_channel_float(self, address: int, channel: int) -> tuple[float, int]:
        payload = self._send_receive(bytes([address, 73, channel]), 5)
        value = struct.unpack(">f", payload[0:4])[0]
        status = payload[4]
        return value, status


# ============================================================
# Data Model
# ============================================================

@dataclass
class Sample:
    no: int
    local_dt: datetime
    utc_dt: datetime
    p1_bar: float
    tob1_c: float

    @property
    def p1_bar_rounded(self) -> float:
        return round(self.p1_bar, 2)

    @property
    def tob1_c_rounded(self) -> float:
        return round(self.tob1_c, 2)


@dataclass
class RecordingSession:
    name: str
    started_at: datetime
    interval_s: float
    rows: list[Sample] = field(default_factory=list)
    stopped_at: datetime | None = None
    serial_number: str = ""
    device_address: int = 1

    @property
    def status(self) -> str:
        return "laeuft" if self.stopped_at is None else "gestoppt"

    def add_row(self, p1_bar: float, tob1_c: float) -> None:
        now_local = datetime.now().astimezone()
        now_utc = datetime.now(timezone.utc)
        self.rows.append(
            Sample(
                no=len(self.rows) + 1,
                local_dt=now_local,
                utc_dt=now_utc,
                p1_bar=p1_bar,
                tob1_c=tob1_c,
            )
        )

    def get_filename(self) -> str:
        date_str = self.started_at.strftime("%Y-%m-%d_%H-%M-%S")
        safe_name = "".join(c if c.isalnum() or c in "-_" else "_" for c in self.name)
        return f"messung_{date_str}_{safe_name}.csv"

    def write_csv(self, path: Path) -> None:
        with path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow([
                "No",
                "Datetime [local time]",
                "Datetime [UTC]",
                "P1 [bar]",
                "TOB1 [C]",
                "P1 rounded [bar]",
                "TOB1 rounded [C]",
            ])
            for row in self.rows:
                writer.writerow([
                    row.no,
                    row.local_dt.strftime("%d.%m.%Y %H:%M:%S"),
                    row.utc_dt.isoformat().replace("+00:00", "Z"),
                    f"{row.p1_bar:.9f}",
                    f"{row.tob1_c:.8f}",
                    f"{row.p1_bar_rounded:.2f}",
                    f"{row.tob1_c_rounded:.2f}",
                ])


# ============================================================
# HTTP Server (fuer die Prezio App)
# ============================================================

class PrezioHTTPHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Keine Log-Ausgabe

    def send_json(self, data, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data, indent=2).encode("utf-8"))

    def send_text(self, text, status=200, content_type="text/plain"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(text.encode("utf-8"))

    def do_GET(self):
        path = unquote(self.path)

        if path == "/health":
            self.send_json({
                "status": "ok",
                "server": "Prezio PC Recorder",
                "timestamp": datetime.now().isoformat()
            })
            return

        if path == "/files":
            files = []
            if DATA_DIR.exists():
                for f in DATA_DIR.glob("*.csv"):
                    stat = f.stat()
                    files.append({
                        "filename": f.name,
                        "name": f.name,
                        "size": stat.st_size,
                        "modified": datetime.fromtimestamp(stat.st_mtime).isoformat()
                    })
            files.sort(key=lambda x: x["modified"], reverse=True)
            self.send_json(files)
            return

        if path.startswith("/files/"):
            filename = path[7:]
            filepath = DATA_DIR / filename
            if filepath.exists() and filepath.suffix.lower() == ".csv":
                content = filepath.read_text(encoding="utf-8")
                self.send_text(content, content_type="text/csv")
            else:
                self.send_json({"error": "File not found"}, 404)
            return

        if path == "/":
            self.send_text("Prezio PC Recorder - HTTP Server laeuft")
            return

        self.send_json({"error": "Not found"}, 404)


def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"


# ============================================================
# GUI Application
# ============================================================

class PrezioRecorderApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("Prezio PC Recorder - KELLER LEO5 + HTTP Server")
        self.geometry("1000x700")
        self.configure(bg="#f0f0f0")

        # Stelle sicher dass data Ordner existiert
        DATA_DIR.mkdir(exist_ok=True)

        self.client = KellerProtocolClient()
        self.recordings: list[RecordingSession] = []
        self.active_recording: RecordingSession | None = None
        self.recording_thread: threading.Thread | None = None
        self.stop_event = threading.Event()
        self.http_server: http.server.HTTPServer | None = None
        self.http_thread: threading.Thread | None = None

        # Variables
        self.port_var = tk.StringVar(value="COM3")
        self.baud_var = tk.StringVar(value="9600")
        self.address_var = tk.StringVar(value="1")
        self.interval_var = tk.StringVar(value="1")
        self.session_name_var = tk.StringVar(value="Messung")

        self.status_var = tk.StringVar(value="Nicht verbunden")
        self.serial_nr_var = tk.StringVar(value="-")
        self.live_p1_var = tk.StringVar(value="-")
        self.live_tob1_var = tk.StringVar(value="-")
        self.http_status_var = tk.StringVar(value="Gestoppt")
        self.local_ip_var = tk.StringVar(value=get_local_ip())
        self.recording_status_var = tk.StringVar(value="Keine Aufzeichnung")
        self.sample_count_var = tk.StringVar(value="0")

        self._build_ui()
        self._refresh_ports()
        self._start_http_server()

        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _build_ui(self) -> None:
        # === HTTP Server Info (oben) ===
        http_frame = ttk.LabelFrame(self, text="HTTP Server (fuer Prezio App)")
        http_frame.pack(fill="x", padx=10, pady=5)

        ttk.Label(http_frame, text="Status:").grid(row=0, column=0, padx=5, pady=5)
        ttk.Label(http_frame, textvariable=self.http_status_var, font=("Segoe UI", 10, "bold")).grid(row=0, column=1, padx=5, pady=5)
        ttk.Label(http_frame, text="IP-Adresse:").grid(row=0, column=2, padx=5, pady=5)
        ttk.Label(http_frame, textvariable=self.local_ip_var, font=("Segoe UI", 10, "bold")).grid(row=0, column=3, padx=5, pady=5)
        ttk.Label(http_frame, text=f"Port: {HTTP_PORT}").grid(row=0, column=4, padx=5, pady=5)
        
        ttk.Label(http_frame, text="In App einstellen:", foreground="blue").grid(row=0, column=5, padx=20, pady=5)

        # === Verbindung ===
        conn_frame = ttk.LabelFrame(self, text="KELLER LEO5 Verbindung")
        conn_frame.pack(fill="x", padx=10, pady=5)

        ttk.Label(conn_frame, text="Port:").grid(row=0, column=0, padx=5, pady=5)
        self.port_combo = ttk.Combobox(conn_frame, textvariable=self.port_var, width=10)
        self.port_combo.grid(row=0, column=1, padx=5, pady=5)
        ttk.Button(conn_frame, text="Aktualisieren", command=self._refresh_ports).grid(row=0, column=2, padx=5, pady=5)

        ttk.Label(conn_frame, text="Baud:").grid(row=0, column=3, padx=5, pady=5)
        ttk.Entry(conn_frame, textvariable=self.baud_var, width=8).grid(row=0, column=4, padx=5, pady=5)

        ttk.Label(conn_frame, text="Adresse:").grid(row=0, column=5, padx=5, pady=5)
        ttk.Entry(conn_frame, textvariable=self.address_var, width=5).grid(row=0, column=6, padx=5, pady=5)

        ttk.Button(conn_frame, text="Verbinden", command=self.connect_device).grid(row=0, column=7, padx=10, pady=5)
        ttk.Button(conn_frame, text="Trennen", command=self.disconnect_device).grid(row=0, column=8, padx=5, pady=5)

        # === Status ===
        status_frame = ttk.LabelFrame(self, text="Geraetestatus")
        status_frame.pack(fill="x", padx=10, pady=5)

        ttk.Label(status_frame, text="Status:").grid(row=0, column=0, padx=5, pady=5)
        ttk.Label(status_frame, textvariable=self.status_var, font=("Segoe UI", 10, "bold")).grid(row=0, column=1, padx=5, pady=5)
        ttk.Label(status_frame, text="Seriennummer:").grid(row=0, column=2, padx=5, pady=5)
        ttk.Label(status_frame, textvariable=self.serial_nr_var).grid(row=0, column=3, padx=5, pady=5)

        # === Live-Werte ===
        live_frame = ttk.LabelFrame(self, text="Live-Werte")
        live_frame.pack(fill="x", padx=10, pady=5)

        ttk.Label(live_frame, text="Druck P1:").grid(row=0, column=0, padx=5, pady=10)
        ttk.Label(live_frame, textvariable=self.live_p1_var, font=("Segoe UI", 16, "bold"), foreground="blue").grid(row=0, column=1, padx=5, pady=10)
        ttk.Label(live_frame, text="bar").grid(row=0, column=2, padx=5, pady=10)

        ttk.Label(live_frame, text="Temperatur TOB1:").grid(row=0, column=3, padx=20, pady=10)
        ttk.Label(live_frame, textvariable=self.live_tob1_var, font=("Segoe UI", 16, "bold"), foreground="orange").grid(row=0, column=4, padx=5, pady=10)
        ttk.Label(live_frame, text="C").grid(row=0, column=5, padx=5, pady=10)

        ttk.Button(live_frame, text="Einzelwert lesen", command=self.read_live_values).grid(row=0, column=6, padx=20, pady=10)

        # === Aufzeichnung ===
        rec_frame = ttk.LabelFrame(self, text="Aufzeichnung")
        rec_frame.pack(fill="x", padx=10, pady=5)

        ttk.Label(rec_frame, text="Name:").grid(row=0, column=0, padx=5, pady=5)
        ttk.Entry(rec_frame, textvariable=self.session_name_var, width=20).grid(row=0, column=1, padx=5, pady=5)

        ttk.Label(rec_frame, text="Intervall (s):").grid(row=0, column=2, padx=5, pady=5)
        ttk.Entry(rec_frame, textvariable=self.interval_var, width=8).grid(row=0, column=3, padx=5, pady=5)

        self.start_btn = ttk.Button(rec_frame, text="AUFZEICHNUNG STARTEN", command=self.start_recording)
        self.start_btn.grid(row=0, column=4, padx=10, pady=5)

        self.stop_btn = ttk.Button(rec_frame, text="STOPPEN", command=self.stop_recording, state="disabled")
        self.stop_btn.grid(row=0, column=5, padx=5, pady=5)

        ttk.Label(rec_frame, text="Status:").grid(row=0, column=6, padx=10, pady=5)
        ttk.Label(rec_frame, textvariable=self.recording_status_var, font=("Segoe UI", 10, "bold")).grid(row=0, column=7, padx=5, pady=5)

        ttk.Label(rec_frame, text="Messpunkte:").grid(row=0, column=8, padx=10, pady=5)
        ttk.Label(rec_frame, textvariable=self.sample_count_var, font=("Segoe UI", 10, "bold")).grid(row=0, column=9, padx=5, pady=5)

        # === Gespeicherte Dateien ===
        files_frame = ttk.LabelFrame(self, text="Gespeicherte Messungen (im data/ Ordner)")
        files_frame.pack(fill="both", expand=True, padx=10, pady=5)

        self.files_tree = ttk.Treeview(files_frame, columns=("name", "size", "modified"), show="headings", height=8)
        self.files_tree.heading("name", text="Dateiname")
        self.files_tree.heading("size", text="Groesse")
        self.files_tree.heading("modified", text="Geaendert")
        self.files_tree.column("name", width=400)
        self.files_tree.column("size", width=100)
        self.files_tree.column("modified", width=200)
        self.files_tree.pack(fill="both", expand=True, padx=5, pady=5)

        ttk.Button(files_frame, text="Aktualisieren", command=self._refresh_files_list).pack(pady=5)

        # === Log ===
        log_frame = ttk.LabelFrame(self, text="Log")
        log_frame.pack(fill="both", expand=True, padx=10, pady=5)

        self.log_text = tk.Text(log_frame, wrap="word", height=8)
        self.log_text.pack(fill="both", expand=True, padx=5, pady=5)

        self._refresh_files_list()

    def _log(self, text: str) -> None:
        ts = datetime.now().strftime("%H:%M:%S")
        self.log_text.insert("end", f"[{ts}] {text}\n")
        self.log_text.see("end")

    def _refresh_ports(self) -> None:
        ports = [p.device for p in serial.tools.list_ports.comports()]
        self.port_combo["values"] = ports
        if ports and self.port_var.get() not in ports:
            self.port_var.set(ports[0] if ports else "COM3")

    def _refresh_files_list(self) -> None:
        for item in self.files_tree.get_children():
            self.files_tree.delete(item)

        if DATA_DIR.exists():
            files = list(DATA_DIR.glob("*.csv"))
            files.sort(key=lambda f: f.stat().st_mtime, reverse=True)
            for f in files:
                stat = f.stat()
                size_kb = stat.st_size / 1024
                modified = datetime.fromtimestamp(stat.st_mtime).strftime("%d.%m.%Y %H:%M:%S")
                self.files_tree.insert("", "end", values=(f.name, f"{size_kb:.1f} KB", modified))

    def _start_http_server(self) -> None:
        try:
            self.http_server = http.server.HTTPServer(("0.0.0.0", HTTP_PORT), PrezioHTTPHandler)
            self.http_thread = threading.Thread(target=self.http_server.serve_forever, daemon=True)
            self.http_thread.start()
            self.http_status_var.set("Laeuft")
            self._log(f"HTTP Server gestartet auf Port {HTTP_PORT}")
        except Exception as e:
            self.http_status_var.set("Fehler")
            self._log(f"HTTP Server Fehler: {e}")

    def connect_device(self) -> None:
        if self.client.is_open:
            self._log("Bereits verbunden.")
            return

        try:
            self.client.open(
                port=self.port_var.get().strip(),
                baudrate=int(self.baud_var.get().strip()),
                timeout=1.0,
            )
            self.status_var.set("Verbunden")
            self._log(f"Verbunden mit {self.port_var.get()}")

            # Wakeup und Seriennummer lesen
            try:
                self.client.wakeup(250)
                serial_nr = self.client.read_serial_number(int(self.address_var.get()))
                self.serial_nr_var.set(str(serial_nr))
                self._log(f"Seriennummer: {serial_nr}")
            except Exception as e:
                self._log(f"Wakeup/SN Fehler: {e}")

        except Exception as e:
            self.status_var.set("Fehler")
            messagebox.showerror("Verbindungsfehler", str(e))
            self._log(f"Verbindungsfehler: {e}")

    def disconnect_device(self) -> None:
        self.stop_recording()
        self.client.close()
        self.status_var.set("Nicht verbunden")
        self._log("Verbindung getrennt")

    def read_live_values(self) -> None:
        if not self.client.is_open:
            messagebox.showwarning("Nicht verbunden", "Bitte zuerst verbinden.")
            return

        try:
            address = int(self.address_var.get())
            p1, _ = self.client.read_channel_float(address, 1)
            tob1, _ = self.client.read_channel_float(address, 4)
            self.live_p1_var.set(f"{p1:.2f}")
            self.live_tob1_var.set(f"{tob1:.2f}")
            self._log(f"Gelesen: P1={p1:.4f} bar, TOB1={tob1:.2f} C")
        except Exception as e:
            messagebox.showerror("Lesefehler", str(e))
            self._log(f"Lesefehler: {e}")

    def start_recording(self) -> None:
        if self.active_recording is not None:
            messagebox.showwarning("Laeuft bereits", "Eine Aufzeichnung laeuft bereits.")
            return

        if not self.client.is_open:
            messagebox.showwarning("Nicht verbunden", "Bitte zuerst verbinden.")
            return

        try:
            interval_s = float(self.interval_var.get().strip())
            if interval_s <= 0:
                raise ValueError("Intervall muss > 0 sein.")
        except Exception as e:
            messagebox.showerror("Fehler", str(e))
            return

        name = self.session_name_var.get().strip() or f"Messung_{len(self.recordings) + 1}"
        session = RecordingSession(
            name=name,
            started_at=datetime.now().astimezone(),
            interval_s=interval_s,
            serial_number=self.serial_nr_var.get(),
            device_address=int(self.address_var.get()),
        )
        self.recordings.append(session)
        self.active_recording = session
        self.stop_event.clear()

        self.recording_status_var.set("LAEUFT")
        self.sample_count_var.set("0")
        self.start_btn.config(state="disabled")
        self.stop_btn.config(state="normal")

        self._log(f"Aufzeichnung gestartet: {name}, Intervall {interval_s}s")

        self.recording_thread = threading.Thread(target=self._recording_loop, daemon=True)
        self.recording_thread.start()

    def _recording_loop(self) -> None:
        address = int(self.address_var.get())
        interval_s = self.active_recording.interval_s if self.active_recording else 1.0

        while not self.stop_event.is_set():
            cycle_start = time.time()
            try:
                p1, _ = self.client.read_channel_float(address, 1)
                tob1, _ = self.client.read_channel_float(address, 4)
                if self.active_recording is not None:
                    self.active_recording.add_row(p1, tob1)
                    self.after(0, self._update_ui, p1, tob1)
            except Exception as e:
                self.after(0, self._log, f"Aufzeichnungsfehler: {e}")

            elapsed = time.time() - cycle_start
            remaining = max(0.0, interval_s - elapsed)
            if self.stop_event.wait(remaining):
                break

    def _update_ui(self, p1: float, tob1: float) -> None:
        self.live_p1_var.set(f"{p1:.2f}")
        self.live_tob1_var.set(f"{tob1:.2f}")
        if self.active_recording:
            self.sample_count_var.set(str(len(self.active_recording.rows)))

    def _enforce_max_files(self, max_files: int = 10) -> None:
        if not DATA_DIR.exists():
            return
        files = sorted(DATA_DIR.glob("*.csv"), key=lambda f: f.stat().st_mtime)
        while len(files) > max_files:
            oldest = files.pop(0)
            try:
                oldest.unlink()
                self._log(f"Aelteste Datei geloescht: {oldest.name}")
            except Exception as e:
                self._log(f"Fehler beim Loeschen: {e}")

    def stop_recording(self) -> None:
        if self.active_recording is None:
            return

        self.stop_event.set()
        if self.recording_thread and self.recording_thread.is_alive():
            self.recording_thread.join(timeout=2.0)

        self.active_recording.stopped_at = datetime.now().astimezone()

        filename = self.active_recording.get_filename()
        filepath = DATA_DIR / filename
        self.active_recording.write_csv(filepath)

        self._enforce_max_files(10)

        self._log(f"Aufzeichnung gestoppt und gespeichert: {filename} ({len(self.active_recording.rows)} Werte)")

        self.recording_status_var.set("Gestoppt")
        self.start_btn.config(state="normal")
        self.stop_btn.config(state="disabled")

        self.active_recording = None
        self._refresh_files_list()

    def _on_close(self) -> None:
        try:
            self.stop_recording()
            self.client.close()
            if self.http_server:
                self.http_server.shutdown()
        finally:
            self.destroy()


if __name__ == "__main__":
    app = PrezioRecorderApp()
    app.mainloop()
