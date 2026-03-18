# Prezio PC Recorder

Windows-Tool zum Auslesen des KELLER LEO5 Drucksensors und Bereitstellen der Daten fuer die Prezio App. Ersetzt den Raspberry Pi fuer Entwicklung und Tests am Windows-PC.

## Features

- Verbindung mit KELLER LEO5 ueber COM-Port
- Live-Anzeige von Druck und Temperatur
- Aufzeichnung mit konfigurierbarem Intervall
- Automatische Speicherung als CSV
- Integrierter HTTP-Server (Port 8080) fuer die Prezio App

## Installation

### Variante A: PrezioHub Installer (empfohlen)

Der PC Recorder ist im **PrezioHub Installer** enthalten (`PrezioHub_Setup_1.0.0.exe`). Nach der Installation steht `PrezioRecorder.exe` zur Verfuegung - kein Python noetig.

Das Tool kann auch direkt aus dem PrezioHub Dashboard unter dem Tab "Tools" gestartet werden.

### Variante B: Aus dem Quellcode

1. Python 3.x installieren
2. PySerial installieren:
   ```
   pip install pyserial
   ```

## Starten

### Als .exe (nach Installation)

Doppelklick auf `PrezioRecorder.exe` oder ueber PrezioHub > Tools > PC Recorder.

### Aus dem Quellcode

Doppelklick auf `start_recorder.bat`

Oder im Terminal:
```
python prezio_recorder.py
```

## Verwendung

1. **Verbinden:**
   - COM-Port auswaehlen (z.B. COM3)
   - "Verbinden" klicken

2. **Aufzeichnen:**
   - Name fuer die Messung eingeben
   - Intervall in Sekunden festlegen
   - "AUFZEICHNUNG STARTEN" klicken
   - "STOPPEN" wenn fertig

3. **App verbinden:**
   - In der Prezio App unter Einstellungen:
   - IP-Adresse: Die angezeigte lokale IP
   - Port: 8080

## Ordnerstruktur

```
pc_recorder/
  prezio_recorder.py    <- Hauptprogramm
  start_recorder.bat    <- Startscript
  requirements.txt      <- Python-Abhaengigkeiten
  data/                 <- Hier werden CSV-Dateien gespeichert
    messung_2026-03-13_xyz.csv
    ...
```

## HTTP Endpunkte

Der integrierte Server stellt diese Endpunkte bereit:

| Endpunkt | Beschreibung |
|----------|--------------|
| GET /health | Server-Status |
| GET /files | Liste aller CSV-Dateien |
| GET /files/{name} | Download einer CSV-Datei |

## Fuer den Raspberry Pi

Das gleiche Skript kann auf dem Raspberry Pi laufen:
1. Python und pyserial installieren
2. Skript kopieren
3. COM-Port auf `/dev/ttyUSB0` oder aehnlich aendern
4. Mit `python3 prezio_recorder.py` starten

## Tipps

- Der HTTP-Server startet automatisch beim Programmstart
- Messungen werden automatisch im `data/` Ordner gespeichert
- Die App kann jederzeit die Dateien abrufen, auch waehrend einer Aufzeichnung

## Siehe auch

- [PrezioHub Anleitung](../PrezioHub_Anleitung.md) - Zentrale Steuerungsoberflaeche
- [Technische Dokumentation](../DOKUMENTATION.md) - Vollstaendige Systemreferenz
