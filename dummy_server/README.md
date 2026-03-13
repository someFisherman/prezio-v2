# Prezio Dummy Server

Dieser Server simuliert den Raspberry Pi für Entwicklung und Tests.

## Voraussetzungen

- Python 3.x (bereits auf den meisten Systemen installiert)

## Server starten

### Option 1: Doppelklick
Doppelklicke auf `start_server.bat`

### Option 2: Terminal
```bash
cd dummy_server
python server.py
```

## Endpunkte

| Endpunkt | Beschreibung |
|----------|--------------|
| `GET /` | Server-Info |
| `GET /health` | Health-Check (für Verbindungstest) |
| `GET /files` | Liste aller CSV-Dateien |
| `GET /files/{name}` | Download einer CSV-Datei |

## Beispiel-Antworten

### GET /health
```json
{
  "status": "ok",
  "server": "Prezio Dummy Server",
  "version": "1.0.0",
  "timestamp": "2026-03-13T16:30:00.000000"
}
```

### GET /files
```json
[
  {
    "filename": "messung_2026-03-13.csv",
    "name": "messung_2026-03-13.csv",
    "size": 1234,
    "modified": "2026-03-13T16:00:00.000000"
  }
]
```

## Eigene Messdaten hinzufügen

1. Erstelle eine CSV-Datei im Format:
   ```csv
   No,Datetime [local time],Datetime [UTC],P1 [bar],TOB1 [°C],P1 rounded [bar],TOB1 rounded [°C]
   1,13.03.2026 15:37:23,2026-03-13T14:37:23.454963Z,-0.001094818,25.71664429,-0.00,25.72
   ```

2. Speichere die Datei im `data/` Ordner

3. Der Server erkennt neue Dateien automatisch

## In der App einstellen

1. Öffne Prezio App → Einstellungen
2. Setze die IP-Adresse auf die angezeigte lokale IP
3. Port: 8080 (Standard)
4. Teste mit "Verbindung testen"

## Für den echten Raspberry Pi

Der gleiche Python-Code kann auf dem Raspberry Pi laufen:
1. Kopiere `server.py` auf den Pi
2. Erstelle einen `data/` Ordner
3. Starte mit `python3 server.py`
4. Optional: Als Systemd-Service einrichten für Autostart
