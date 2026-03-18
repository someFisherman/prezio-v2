# PrezioHub - Anleitung

**Version:** 1.1.0  
**Stand:** Maerz 2026  
**Entwickelt fuer:** Soleco AG  

---

## Was ist PrezioHub?

PrezioHub ist die zentrale Steuerungsoberflaeche fuer das gesamte Prezio-Oekosystem. Es buendelt alle Werkzeuge, Steuerungsfunktionen und Dokumentationen in einer einzigen Desktop-Anwendung.

### Enthaltene Werkzeuge

| Tool | Funktion |
|------|----------|
| **PrezioHub** | Zentrale Steuerung, Pi-Verwaltung, Monitoring, Firmware-Updates |
| **PrezioImager** | SD-Karten mit Raspberry Pi OS flashen (vollautomatisch) |
| **PrezioRecorder** | Windows-Version des Sensor-Recorders (KELLER LEO5) |
| **PrezioDummy** | Mock-Server fuer Entwicklung ohne echten Sensor |

---

## Installation

### Variante A: Installer (empfohlen)

1. `PrezioHub_Setup_1.0.0.exe` ausfuehren
2. Installationsverzeichnis waehlen (Standard: `C:\Program Files\PrezioHub`)
3. Optionale Desktop-Verknuepfungen waehlen
4. Installation abschliessen

Alle Tools sind sofort einsatzbereit - kein Python oder andere Software noetig.

### Variante B: Aus dem Quellcode

```
cd prezio_v2/prezio_hub
python prezio_hub.py
```

Voraussetzung: Python 3.x mit paramiko installiert.

---

## Firmware-Cache (wichtig!)

PrezioHub laedt beim Start automatisch die neueste Pi-Firmware von GitHub herunter und speichert sie lokal unter `%LOCALAPPDATA%\PrezioHub\firmware_cache\`. Dieser Cache wird sowohl vom Hub (fuer Pi-Updates) als auch vom PrezioImager (fuer SD-Karten-Flashen) verwendet.

**Beim Start mit Internet:**
- Die Dateien `pi_recorder.py`, `setup_pi.sh`, `requirements.txt` und `howto.txt` werden von GitHub (`main`-Branch) heruntergeladen und im Cache gespeichert/ueberschrieben.

**Beim Start ohne Internet:**
- Falls ein Cache vorhanden ist: Rotes Banner zeigt "Alte Version wird verwendet"
- Falls kein Cache vorhanden ist: Rotes Banner zeigt "Bitte Hub mit Internet starten"

**Wichtig:** Den Hub mindestens einmal mit Internetverbindung starten, bevor man SD-Karten flasht oder Pi-Updates durchfuehrt.

---

## Tabs im Ueberblick

### 1. Dashboard (Pi-Status)

Zeigt den aktuellen Zustand des Raspberry Pi Recorders in Echtzeit:

- **Verbindungsstatus:** Erreichbar / Nicht erreichbar
- **Sensor:** Verbunden / Nicht verbunden, Seriennummer
- **Aufnahme:** Status der laufenden Aufzeichnung
- **Live-Werte:** P1 (bar) und TOB1 (Grad C) in Echtzeit
- **Update-Banner:** Oranges Banner erscheint automatisch wenn die Pi-Firmware veraltet ist

**Aktionen:**
- **Aktualisieren** - Manuell den Pi-Status und Live-Werte abfragen

Das Dashboard aktualisiert sich automatisch alle 5 Sekunden. Wenn der Pi eine veraltete Firmware hat, erscheint sofort ein oranges Banner mit dem Hinweis "UPDATE FAELLIG" und einem Button "Zur Pi-Steuerung".

**Voraussetzung:** Computer muss mit dem WiFi "Prezio-Recorder" verbunden sein.

### 2. Pi-Steuerung

Direkte Kontrolle ueber den Raspberry Pi:

**Aktionen:**
- **SSH oeffnen** - Startet PowerShell mit SSH-Verbindung zum Pi
- **Service neustarten** - Startet den Prezio-Recorder-Service neu
- **Pi rebooten** - Startet den gesamten Pi neu (60s nicht erreichbar)
- **WiFi aus (120s)** - Schaltet WiFi kurzzeitig ab

**Firmware-Update:**
- **Pi-Firmware pruefen** - Vergleicht die Pi-Version mit der gecachten Version
- Falls ein Update verfuegbar ist: Button **"Jetzt updaten"** erscheint
- Das Update laedt die gecachte `pi_recorder.py` per SFTP auf den Pi und startet den Service neu
- Kein Internet noetig waehrend des Updates (alles geht ueber das Pi-WiFi)

**Service-Logs:**
- **Logs laden** - Zeigt die letzten 80 Zeilen der Pi-Logs

### 3. Aufzeichnung

Fernsteuerung der Aufzeichnung auf dem Raspberry Pi:

- **Status:** Zeigt ob eine Aufzeichnung laeuft, Name, Dauer, Anzahl Messpunkte
- **Starten:** Neue Aufzeichnung mit Name, PN, Medium und Intervall starten
- **Stoppen:** Laufende Aufzeichnung beenden

### 4. Tools

Startet die anderen Prezio-Werkzeuge:

- **PrezioImager** - SD-Karten Flash Tool (benoetigt Admin-Rechte)
- **PC Recorder** - Windows-Recorder mit GUI
- **Dummy Server** - Mock-Server in einem Konsolenfenster

### 5. Supabase

Zugriff auf die Cloud-Datenbank und den Datei-Storage:

- **Dashboard oeffnen** - Oeffnet das Supabase Web-Dashboard im Browser
- **Ordner laden** - Laedt Protokoll-Ordner aus dem Supabase Storage (sortiert nach Datum, neueste oben)
- **Datei herunterladen** - Einzelne Datei herunterladen
- **Als ZIP herunterladen** - Gesamten Ordner als ZIP-Archiv herunterladen

### 6. Dokumentation

Zugriff auf alle Projekt-Dokumentationen direkt aus dem Hub.

---

## Netzwerk-Konfiguration

| Einstellung | Wert |
|-------------|------|
| Pi IP-Adresse | `192.168.4.1` |
| Pi HTTP-Port | `8080` |
| Pi SSH-User | `pi` |
| Pi SSH-Passwort | `Prezio2000!` |
| WiFi SSID | `Prezio-Recorder` |
| WiFi Passwort | `prezio2026` |
| WiFi Land | CH (Schweiz) |

---

## Pi-Firmware-Update: So funktioniert es

### Ablauf

1. Hub mit Internetverbindung starten (Cache wird aktualisiert)
2. Mit WiFi "Prezio-Recorder" verbinden
3. Im Dashboard: Oranges Banner zeigt an, wenn ein Update verfuegbar ist
4. Zum Tab "Pi-Steuerung" wechseln
5. "Pi-Firmware pruefen" klicken (oder direkt "Jetzt updaten" wenn Banner angezeigt wird)
6. "Jetzt updaten" klicken:
   - Die gecachte `pi_recorder.py` wird per SFTP auf den Pi hochgeladen
   - Der Service `prezio-recorder` wird automatisch neugestartet
7. Bestaetigung wird angezeigt

### Technischer Hintergrund

- Der Hub vergleicht die `VERSION` in der gecachten `pi_recorder.py` mit der Version auf dem Pi (abgefragt ueber `/health`)
- Das Update nutzt SFTP (SSH File Transfer), daher muss man nur mit dem Pi-WiFi verbunden sein
- **Kein Internet waehrend des Updates noetig** - die Datei kommt aus dem lokalen Cache

---

## Fehlerbehebung

### Pi nicht erreichbar

| Problem | Loesung |
|---------|---------|
| Dashboard zeigt "Nicht erreichbar" | Pruefen ob PC mit WiFi "Prezio-Recorder" verbunden ist |
| WiFi nicht sichtbar | Pi hat Strom? 3-5 Minuten warten nach dem ersten Einschalten |
| WiFi verbunden aber kein Zugriff | `http://192.168.4.1:8080/health` im Browser testen |

### Firmware-Update funktioniert nicht

| Problem | Loesung |
|---------|---------|
| "Kein Cache vorhanden" | Hub einmal mit Internet starten |
| "Pi nicht erreichbar" | Mit WiFi "Prezio-Recorder" verbinden |
| Upload fehlgeschlagen | SSH-Zugangsdaten pruefen (pi / Prezio2000!) |

### PrezioImager Fehler

| Problem | Loesung |
|---------|---------|
| "Cache aelter als 24 Stunden" | Imager mit Internet starten, damit neue Firmware geladen wird |
| "Keine Firmware verfuegbar" | Hub oder Imager einmal mit Internet starten |
| Nichts passiert beim Klick | UAC-Dialog koennte im Hintergrund sein (Taskleiste pruefen) |

---

## Fuer Entwickler

### Neues Pi-Update veroeffentlichen

So wird ein Update fuer alle Raspberry Pis veroeffentlicht:

1. `pi_recorder.py` aendern (z.B. Bugfix, neue Funktion)
2. `VERSION = "1.2.0"` in `pi_recorder.py` hochsetzen
3. `git add . && git commit -m "Pi Recorder v1.2.0 - Beschreibung" && git push`
4. **Fertig!**

PrezioHub und PrezioImager ziehen automatisch die neueste Version von GitHub (`main`-Branch) beim naechsten Start. Kein GitHub Release noetig.

Falls sich auch `setup_pi.sh` oder `requirements.txt` geaendert haben, diese ebenfalls committen und pushen.

### Neues Hub-Update verteilen

Der Hub selbst hat kein Auto-Update. Neues Hub-Update:

1. Code aendern, `VERSION` hochsetzen in `prezio_hub.py`
2. `python build_all.py` ausfuehren
3. Inno Setup kompilieren (`prezio_installer.iss`)
4. Die neue `PrezioHub_Setup_X.X.X.exe` manuell verteilen

### Distribution bauen

```bash
cd prezio_v2/prezio_hub
python build_all.py
```

Erzeugt `dist/PrezioHub/` mit allen Executables und Dokumentationen.

### Installer erstellen

1. Inno Setup installieren: https://jrsoftware.org/isdl.php
2. `prezio_installer.iss` in Inno Setup oeffnen
3. "Compile" klicken
4. Ergebnis: `installer_output/PrezioHub_Setup_X.X.X.exe`

---

*Stand: Maerz 2026 - Soleco AG*
