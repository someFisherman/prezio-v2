#!/usr/bin/env python3
"""
Prezio Pi Recorder - Headless KELLER LEO5 + HTTP API

Runs on Raspberry Pi without GUI. Starts automatically via systemd.
The Prezio smartphone app connects via WiFi AP and controls recordings
through the HTTP API.

API Endpoints:
  GET  /health            - Health check + sensor status
  GET  /files             - List CSV files
  GET  /files/{name}      - Download CSV file
  DELETE /files/{name}    - Delete CSV file
  POST /recording/start   - Start recording
  POST /recording/stop    - Stop recording
  GET  /recording/status  - Current recording status
"""

import csv
import glob
import http.server
import json
import os
import struct
import threading
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import unquote

import serial
import serial.tools.list_ports

# ============================================================
# Configuration
# ============================================================

DATA_DIR = Path(__file__).parent / "data"
HTTP_PORT = 8080
DEFAULT_INTERVAL_S = 10
MAX_FILES = 10
SENSOR_BAUD = 9600
SENSOR_ADDRESS = 1

# ============================================================
# KELLER Protocol (identical to pc_recorder)
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
            raise KellerError("Serial connection not open.")
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
                f"Timeout reading. Expected {size} bytes, got {len(buf)}."
            )
        return bytes(buf)

    def _send_receive(self, command_wo_crc: bytes, expected_payload_len: int) -> bytes:
        if not self.ser or not self.ser.is_open:
            raise KellerError("Serial connection not open.")
        frame = command_wo_crc + crc16_keller(command_wo_crc)
        expected_total = 2 + expected_payload_len + 2
        self.ser.reset_input_buffer()
        self.ser.write(frame)
        self.ser.flush()
        if self.echo_on:
            echo = self._read_exact(len(frame))
            if echo != frame:
                raise KellerError("Echo mismatch.")
        answer = self._read_exact(expected_total)
        payload_plus_header = answer[:-2]
        crc_rx = answer[-2:]
        crc_calc = crc16_keller(payload_plus_header)
        if crc_rx != crc_calc:
            raise KellerError("CRC mismatch.")
        if answer[0] != command_wo_crc[0]:
            raise KellerError("Wrong device address in response.")
        if answer[1] > 127:
            error_code = answer[2] if len(answer) > 2 else None
            raise KellerError(f"Device error: code={error_code}")
        if answer[1] != command_wo_crc[1]:
            raise KellerError("Wrong function code in response.")
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
    pn: int
    medium: str
    rows: list[Sample] = field(default_factory=list)
    stopped_at: datetime | None = None
    serial_number: str = ""
    device_address: int = SENSOR_ADDRESS

    @property
    def is_running(self) -> bool:
        return self.stopped_at is None

    def add_row(self, p1_bar: float, tob1_c: float) -> None:
        now_local = datetime.now().astimezone()
        now_utc = datetime.now(timezone.utc)
        self.rows.append(Sample(
            no=len(self.rows) + 1,
            local_dt=now_local,
            utc_dt=now_utc,
            p1_bar=p1_bar,
            tob1_c=tob1_c,
        ))

    def get_filename(self) -> str:
        date_str = self.started_at.strftime("%Y-%m-%d_%H-%M-%S")
        safe_name = "".join(c if c.isalnum() or c in "-_" else "_" for c in self.name)
        return f"messung_{date_str}_{safe_name}.csv"

    def write_csv(self, path: Path) -> None:
        with path.open("w", newline="", encoding="utf-8") as f:
            f.write(f"# Name: {self.name}\n")
            f.write(f"# PN: {self.pn}\n")
            f.write(f"# Medium: {self.medium}\n")
            f.write(f"# Interval: {self.interval_s}\n")
            f.write(f"# Started: {self.started_at.isoformat()}\n")
            if self.stopped_at:
                f.write(f"# Stopped: {self.stopped_at.isoformat()}\n")
            f.write(f"# Samples: {len(self.rows)}\n")
            f.write(f"# SerialNumber: {self.serial_number}\n")

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
# Recorder Engine (headless)
# ============================================================

class PrezioRecorder:
    def __init__(self) -> None:
        DATA_DIR.mkdir(exist_ok=True)
        self.client = KellerProtocolClient()
        self.active_recording: RecordingSession | None = None
        self.recording_thread: threading.Thread | None = None
        self.stop_event = threading.Event()
        self.lock = threading.Lock()
        self.sensor_connected = False
        self.serial_number = ""
        self.last_p1: float | None = None
        self.last_tob1: float | None = None
        self._sensor_port: str | None = None

    def auto_connect_sensor(self) -> bool:
        ports = self._find_serial_ports()
        for port in ports:
            try:
                self.client.open(port, baudrate=SENSOR_BAUD, timeout=1.0)
                self.client.wakeup(250)
                sn = self.client.read_serial_number(SENSOR_ADDRESS)
                self.serial_number = str(sn)
                self.sensor_connected = True
                self._sensor_port = port
                _log(f"Sensor connected on {port}, SN: {sn}")
                return True
            except Exception as e:
                self.client.close()
                _log(f"Port {port} failed: {e}")
        _log("No sensor found on any port.")
        return False

    def reconnect_sensor(self) -> bool:
        self.client.close()
        self.sensor_connected = False
        return self.auto_connect_sensor()

    def _find_serial_ports(self) -> list[str]:
        ports = [p.device for p in serial.tools.list_ports.comports()]
        for pattern in ["/dev/ttyUSB*", "/dev/ttyACM*"]:
            ports.extend(glob.glob(pattern))
        return list(dict.fromkeys(ports))

    def start_recording(self, name: str, pn: int, medium: str,
                        interval_s: float = DEFAULT_INTERVAL_S) -> dict:
        with self.lock:
            if self.active_recording is not None:
                return {"error": "Recording already active."}
            if not self.sensor_connected:
                if not self.reconnect_sensor():
                    return {"error": "No sensor connected."}

            session = RecordingSession(
                name=name,
                started_at=datetime.now().astimezone(),
                interval_s=interval_s,
                pn=pn,
                medium=medium,
                serial_number=self.serial_number,
                device_address=SENSOR_ADDRESS,
            )
            self.active_recording = session
            self.stop_event.clear()

        self.recording_thread = threading.Thread(
            target=self._recording_loop, daemon=True
        )
        self.recording_thread.start()
        _log(f"Recording started: {name}, PN{pn}, {medium}, {interval_s}s interval")
        return {"status": "started", "name": name}

    def stop_recording(self) -> dict:
        with self.lock:
            if self.active_recording is None:
                return {"error": "No active recording."}
            self.stop_event.set()

        if self.recording_thread and self.recording_thread.is_alive():
            self.recording_thread.join(timeout=5.0)

        with self.lock:
            session = self.active_recording
            if session is None:
                return {"error": "No active recording."}
            session.stopped_at = datetime.now().astimezone()
            filename = session.get_filename()
            filepath = DATA_DIR / filename
            session.write_csv(filepath)
            sample_count = len(session.rows)
            self.active_recording = None

        self._enforce_max_files()
        _log(f"Recording stopped: {filename} ({sample_count} samples)")
        return {"status": "stopped", "filename": filename, "samples": sample_count}

    def get_recording_status(self) -> dict:
        with self.lock:
            if self.active_recording is None:
                return {
                    "recording": False,
                    "sensor_connected": self.sensor_connected,
                    "last_p1": self.last_p1,
                    "last_tob1": self.last_tob1,
                }
            s = self.active_recording
            elapsed = (datetime.now().astimezone() - s.started_at).total_seconds()
            return {
                "recording": True,
                "name": s.name,
                "pn": s.pn,
                "medium": s.medium,
                "interval_s": s.interval_s,
                "started_at": s.started_at.isoformat(),
                "elapsed_seconds": int(elapsed),
                "sample_count": len(s.rows),
                "sensor_connected": self.sensor_connected,
                "last_p1": self.last_p1,
                "last_tob1": self.last_tob1,
            }

    def _recording_loop(self) -> None:
        while not self.stop_event.is_set():
            cycle_start = time.time()
            try:
                p1, _ = self.client.read_channel_float(SENSOR_ADDRESS, 1)
                tob1, _ = self.client.read_channel_float(SENSOR_ADDRESS, 4)
                with self.lock:
                    self.last_p1 = round(p1, 4)
                    self.last_tob1 = round(tob1, 2)
                    if self.active_recording is not None:
                        self.active_recording.add_row(p1, tob1)
            except KellerError as e:
                _log(f"Sensor read error: {e}")
                self.sensor_connected = False
                try:
                    self.reconnect_sensor()
                except Exception:
                    pass
            except Exception as e:
                _log(f"Recording loop error: {e}")

            interval = DEFAULT_INTERVAL_S
            with self.lock:
                if self.active_recording:
                    interval = self.active_recording.interval_s
            elapsed = time.time() - cycle_start
            remaining = max(0.0, interval - elapsed)
            if self.stop_event.wait(remaining):
                break

    def _enforce_max_files(self) -> None:
        if not DATA_DIR.exists():
            return
        files = sorted(DATA_DIR.glob("*.csv"), key=lambda f: f.stat().st_mtime)
        while len(files) > MAX_FILES:
            oldest = files.pop(0)
            try:
                oldest.unlink()
                _log(f"Removed oldest file: {oldest.name}")
            except Exception as e:
                _log(f"Error removing file: {e}")

    def get_health(self) -> dict:
        return {
            "status": "ok",
            "server": "Prezio Pi Recorder",
            "sensor_connected": self.sensor_connected,
            "serial_number": self.serial_number,
            "sensor_port": self._sensor_port,
            "recording": self.active_recording is not None,
            "timestamp": datetime.now().isoformat(),
        }

    def shutdown(self) -> None:
        if self.active_recording:
            self.stop_recording()
        self.client.close()


# ============================================================
# HTTP Server
# ============================================================

_recorder: PrezioRecorder | None = None


class PrezioHTTPHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _send_json(self, data, status=200):
        body = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _send_text(self, text, status=200, content_type="text/plain"):
        body = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self) -> bytes:
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length) if length > 0 else b""

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        path = unquote(self.path)
        rec = _recorder
        if rec is None:
            self._send_json({"error": "Server not ready"}, 503)
            return

        if path == "/health":
            self._send_json(rec.get_health())
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
                        "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                    })
            files.sort(key=lambda x: x["modified"], reverse=True)
            self._send_json(files)
            return

        if path.startswith("/files/"):
            filename = path[7:]
            filepath = DATA_DIR / filename
            if filepath.exists() and filepath.suffix.lower() == ".csv":
                content = filepath.read_text(encoding="utf-8")
                self._send_text(content, content_type="text/csv")
            else:
                self._send_json({"error": "File not found"}, 404)
            return

        if path == "/recording/status":
            self._send_json(rec.get_recording_status())
            return

        if path == "/":
            self._send_text("Prezio Pi Recorder - HTTP API running")
            return

        self._send_json({"error": "Not found"}, 404)

    def do_POST(self):
        path = unquote(self.path)
        rec = _recorder
        if rec is None:
            self._send_json({"error": "Server not ready"}, 503)
            return

        if path == "/recording/start":
            try:
                body = json.loads(self._read_body() or b"{}")
            except json.JSONDecodeError:
                self._send_json({"error": "Invalid JSON"}, 400)
                return

            name = body.get("name", "").strip()
            if not name:
                self._send_json({"error": "Field 'name' is required."}, 400)
                return

            pn = int(body.get("pn", 25))
            medium = body.get("medium", "air")
            interval_s = float(body.get("interval_s", DEFAULT_INTERVAL_S))

            if medium not in ("air", "water"):
                self._send_json({"error": "Medium must be 'air' or 'water'."}, 400)
                return
            if interval_s < 1:
                self._send_json({"error": "Interval must be >= 1 second."}, 400)
                return

            result = rec.start_recording(name, pn, medium, interval_s)
            status = 200 if "status" in result else 409
            self._send_json(result, status)
            return

        if path == "/recording/stop":
            result = rec.stop_recording()
            status = 200 if "status" in result else 409
            self._send_json(result, status)
            return

        self._send_json({"error": "Not found"}, 404)

    def do_DELETE(self):
        path = unquote(self.path)
        if path.startswith("/files/"):
            filename = path[7:]
            filepath = DATA_DIR / filename
            if filepath.exists() and filepath.suffix.lower() == ".csv":
                try:
                    filepath.unlink()
                    self._send_json({"status": "deleted", "filename": filename})
                except Exception as e:
                    self._send_json({"error": str(e)}, 500)
            else:
                self._send_json({"error": "File not found"}, 404)
            return

        self._send_json({"error": "Not found"}, 404)


# ============================================================
# Logging
# ============================================================

def _log(msg: str) -> None:
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


# ============================================================
# Main
# ============================================================

def main():
    global _recorder

    _log("Prezio Pi Recorder starting...")
    _log(f"Data directory: {DATA_DIR}")
    _log(f"HTTP port: {HTTP_PORT}")

    DATA_DIR.mkdir(exist_ok=True)
    _recorder = PrezioRecorder()

    _log("Searching for sensor...")
    if _recorder.auto_connect_sensor():
        _log(f"Sensor ready (SN: {_recorder.serial_number})")
    else:
        _log("WARNING: No sensor found. Will retry on first recording start.")

    server = http.server.HTTPServer(("0.0.0.0", HTTP_PORT), PrezioHTTPHandler)
    _log(f"HTTP server listening on 0.0.0.0:{HTTP_PORT}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        _log("Shutting down...")
    finally:
        _recorder.shutdown()
        server.server_close()
        _log("Goodbye.")


if __name__ == "__main__":
    main()
