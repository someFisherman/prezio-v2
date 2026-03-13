#!/usr/bin/env python3
"""
Prezio Dummy Server - Simuliert den Raspberry Pi HTTP-Server
Führe dieses Script aus um den Server zu starten.
"""

import http.server
import json
import os
import socket
from datetime import datetime
from pathlib import Path
from urllib.parse import unquote

# Konfiguration
PORT = 8080
DATA_DIR = Path(__file__).parent / "data"

class PrezioRequestHandler(http.server.BaseHTTPRequestHandler):
    """HTTP Request Handler für den Prezio Dummy Server"""
    
    def log_message(self, format, *args):
        """Überschreibt die Log-Ausgabe für bessere Lesbarkeit"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"[{timestamp}] {args[0]}")
    
    def send_json_response(self, data, status=200):
        """Sendet eine JSON-Antwort"""
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data, indent=2).encode("utf-8"))
    
    def send_text_response(self, text, status=200, content_type="text/plain"):
        """Sendet eine Text-Antwort"""
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(text.encode("utf-8"))
    
    def do_GET(self):
        """Verarbeitet GET-Anfragen"""
        path = unquote(self.path)
        
        # Health Check
        if path == "/health":
            self.send_json_response({
                "status": "ok",
                "server": "Prezio Dummy Server",
                "version": "1.0.0",
                "timestamp": datetime.now().isoformat()
            })
            return
        
        # Dateiliste
        if path == "/files":
            files = self.get_file_list()
            self.send_json_response(files)
            return
        
        # Einzelne Datei herunterladen
        if path.startswith("/files/"):
            filename = path[7:]  # Entferne "/files/"
            self.serve_file(filename)
            return
        
        # Root - Zeigt Server-Info
        if path == "/" or path == "":
            info = f"""
╔══════════════════════════════════════════════════════════════╗
║            PREZIO DUMMY SERVER - RASPBERRY PI SIMULATION      ║
╠══════════════════════════════════════════════════════════════╣
║  Endpunkte:                                                   ║
║    GET /health         - Server-Status                        ║
║    GET /files          - Liste aller CSV-Dateien              ║
║    GET /files/{{name}}   - Download einer CSV-Datei            ║
║                                                               ║
║  Daten-Verzeichnis: {str(DATA_DIR):<40} ║
║  CSV-Dateien: {len(list(DATA_DIR.glob('*.csv'))) if DATA_DIR.exists() else 0:<47} ║
╚══════════════════════════════════════════════════════════════╝
"""
            self.send_text_response(info)
            return
        
        # 404 für alles andere
        self.send_json_response({"error": "Not found"}, 404)
    
    def get_file_list(self):
        """Gibt eine Liste aller CSV-Dateien zurück"""
        if not DATA_DIR.exists():
            return []
        
        files = []
        for f in DATA_DIR.glob("*.csv"):
            stat = f.stat()
            files.append({
                "filename": f.name,
                "name": f.name,
                "size": stat.st_size,
                "modified": datetime.fromtimestamp(stat.st_mtime).isoformat()
            })
        
        # Sortiere nach Änderungsdatum (neueste zuerst)
        files.sort(key=lambda x: x["modified"], reverse=True)
        return files
    
    def serve_file(self, filename):
        """Sendet eine CSV-Datei"""
        filepath = DATA_DIR / filename
        
        if not filepath.exists():
            self.send_json_response({"error": f"File not found: {filename}"}, 404)
            return
        
        if not filepath.suffix.lower() == ".csv":
            self.send_json_response({"error": "Only CSV files are allowed"}, 403)
            return
        
        try:
            content = filepath.read_text(encoding="utf-8")
            self.send_text_response(content, content_type="text/csv")
        except Exception as e:
            self.send_json_response({"error": str(e)}, 500)


def get_local_ip():
    """Ermittelt die lokale IP-Adresse"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"


def main():
    # Erstelle Daten-Verzeichnis falls nicht vorhanden
    DATA_DIR.mkdir(exist_ok=True)
    
    # Prüfe ob Beispieldaten existieren
    csv_files = list(DATA_DIR.glob("*.csv"))
    
    local_ip = get_local_ip()
    
    print()
    print("╔══════════════════════════════════════════════════════════════╗")
    print("║          PREZIO DUMMY SERVER - RASPBERRY PI SIMULATION       ║")
    print("╠══════════════════════════════════════════════════════════════╣")
    print(f"║  Server läuft auf:                                           ║")
    print(f"║    • http://localhost:{PORT:<44} ║")
    print(f"║    • http://{local_ip}:{PORT:<41} ║")
    print("║                                                               ║")
    print(f"║  Daten-Verzeichnis: {str(DATA_DIR):<40} ║")
    print(f"║  CSV-Dateien gefunden: {len(csv_files):<37} ║")
    print("║                                                               ║")
    print("║  In der App einstellen:                                       ║")
    print(f"║    IP-Adresse: {local_ip:<45} ║")
    print(f"║    Port: {PORT:<51} ║")
    print("║                                                               ║")
    print("║  Drücke Ctrl+C zum Beenden                                    ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    print()
    
    if len(csv_files) == 0:
        print("⚠️  HINWEIS: Keine CSV-Dateien im Daten-Verzeichnis gefunden!")
        print(f"   Lege CSV-Dateien in '{DATA_DIR}' ab.")
        print()
    else:
        print("📁 Verfügbare CSV-Dateien:")
        for f in csv_files:
            print(f"   • {f.name}")
        print()
    
    # Starte Server
    with http.server.HTTPServer(("0.0.0.0", PORT), PrezioRequestHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n\n👋 Server beendet.")


if __name__ == "__main__":
    main()
