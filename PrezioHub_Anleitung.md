# PrezioHub - Anleitung

**Version:** 1.0.0  
**Stand:** Maerz 2026  
**Entwickelt fuer:** Soleco AG  

---

## Was ist PrezioHub?

PrezioHub ist die zentrale Steuerungsoberflaeche fuer das gesamte Prezio-Oekosystem. Es buendelt alle Werkzeuge, Steuerungsfunktionen und Dokumentationen in einer einzigen Desktop-Anwendung.

### Enthaltene Werkzeuge

| Tool | Funktion |
|------|----------|
| **PrezioHub** | Zentrale Steuerung, Pi-Verwaltung, Monitoring |
| **PrezioImager** | SD-Karten mit Raspberry Pi OS flashen |
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

Voraussetzung: Python 3.x installiert.

---

## Tabs im Ueberblick

PrezioHub ist in sechs Tabs organisiert:

### 1. Dashboard (Pi-Status)

Zeigt den aktuellen Zustand des Raspberry Pi Recorders in Echtzeit:

- **Verbindungsstatus:** Erreichbar / Nicht erreichbar
- **Sensor:** Verbunden / Nicht verbunden, Seriennummer
- **Aufnahme:** Status der laufenden Aufzeichnung
- **Live-Werte:** P1 (bar) und TOB1 (Grad C) in Echtzeit

**Aktionen:**
- **Aktualisieren** - Manuell den Pi-Status und Live-Werte abfragen (oben rechts)

Das Dashboard aktualisiert sich automatisch alle 5 Sekunden wenn der Tab aktiv ist.

**Voraussetzung:** Computer muss mit dem WiFi "Prezio-Recorder" verbunden sein.

### 2. SSH / Terminal

Oeffnet eine PowerShell mit automatischer SSH-Verbindung zum Pi.

- **SSH oeffnen** - Startet `ssh pi@192.168.4.1` in einem neuen PowerShell-Fenster
- **Passwort:** Wird automatisch angezeigt (nicht automatisch eingegeben aus Sicherheitsgruenden)

**Typische SSH-Befehle auf dem Pi:**

```bash
# Service-Logs live anzeigen
sudo journalctl -u prezio-recorder -f

# Service neustarten
sudo systemctl restart prezio-recorder

# Service-Status pruefen
sudo systemctl status prezio-recorder

# Auth-Key anzeigen
cat /home/pi/prezio_key.txt

# Freien Speicherplatz pruefen
df -h
```

### 3. Aufzeichnung

Fernsteuerung der Aufzeichnung auf dem Raspberry Pi:

- **Status:** Zeigt ob eine Aufzeichnung laeuft, Name, Dauer, Anzahl Messpunkte
- **Starten:** Neue Aufzeichnung mit Name, PN, Medium und Intervall starten
- **Stoppen:** Laufende Aufzeichnung beenden

**Hinweis:** Die Aufzeichnung laeuft auf dem Pi, nicht auf dem PC. Der PC ist nur die Fernbedienung.

### 4. Tools

Startet die anderen Prezio-Werkzeuge:

- **PrezioImager** - Oeffnet das SD-Karten Flash Tool (benoetigt Admin-Rechte, UAC-Dialog erscheint)
- **PC Recorder** - Oeffnet den Windows-Recorder mit GUI
- **Dummy Server** - Startet den Mock-Server in einem Konsolenfenster

### 5. Supabase

Zugriff auf die Cloud-Datenbank und den Datei-Storage:

**Datenbank:**
- **Dashboard oeffnen** - Oeffnet das Supabase Web-Dashboard im Browser
- **Rohdaten (DB)** - Zeigt die letzten 30 CSV-Uploads (Tabelle `rohdaten`)
- **Protokolle (DB)** - Zeigt die letzten 30 Protokolle (Tabelle `protokolle`)

**Protokoll-Storage:**
- **Ordner laden** - Laedt alle Protokoll-Ordner aus dem Supabase Storage
- Ordner aufklappen um die enthaltenen Dateien (PDF, CSV) zu sehen
- **Datei herunterladen** - Einzelne Datei herunterladen
- **Als ZIP herunterladen** - Gesamten Ordner als ZIP-Archiv herunterladen

### 6. Dokumentation

Zugriff auf alle Projekt-Dokumentationen:

| Dokument | Inhalt |
|----------|--------|
| Projekt-Uebersicht | Prezio App Features, Architektur, CSV-Format |
| Technische Dokumentation | Vollstaendige Referenz aller Komponenten |
| App Store & Google Play | iOS/Android Signierung und Deployment |
| Pi Image klonen | SD-Karte sichern und auf neue Pis flashen |
| Raspberry Pi Ersteinrichtung | Neuen Recorder von Grund auf einrichten |
| PC Recorder Handbuch | KELLER LEO5 unter Windows auslesen |
| Dummy Server | Mock-Server fuer Entwicklung |
| PrezioHub Anleitung | Dieses Dokument |

---

## Netzwerk-Konfiguration

PrezioHub kommuniziert mit dem Raspberry Pi ueber HTTP:

| Einstellung | Wert |
|-------------|------|
| Pi IP-Adresse | `192.168.4.1` |
| Pi HTTP-Port | `8080` |
| Pi SSH-User | `pi` (konfigurierbar in prezio_hub.py) |
| Pi SSH-Passwort | `Prezio2000!` (konfigurierbar in prezio_hub.py) |
| WiFi SSID | `Prezio-Recorder` |
| WiFi Passwort | `prezio2026` |

> **Hinweis:** SSH-Zugangsdaten werden in `prezio_hub.py` unter `PI_USER` und `PI_PASS` konfiguriert. Wenn du den Pi mit anderen Zugangsdaten eingerichtet hast, passe diese Werte an.

**Wichtig:** Der PC muss mit dem WiFi "Prezio-Recorder" verbunden sein, damit die Pi-Steuerung funktioniert.

---

## Fehlerbehebung

### PrezioHub startet nicht

| Problem | Loesung |
|---------|---------|
| "Python nicht gefunden" | Installer-Version verwenden (kein Python noetig) |
| Fenster schliesst sofort | Aus der Kommandozeile starten um Fehlermeldung zu sehen |

### Pi nicht erreichbar

| Problem | Loesung |
|---------|---------|
| Dashboard zeigt "Nicht erreichbar" | Pruefen ob PC mit WiFi "Prezio-Recorder" verbunden ist |
| WiFi nicht sichtbar | Pi hat Strom? 60 Sekunden warten nach dem Einschalten |
| WiFi verbunden aber kein Zugriff | `http://192.168.4.1:8080/health` im Browser testen |

### PrezioImager startet nicht

| Problem | Loesung |
|---------|---------|
| Nichts passiert beim Klick | UAC-Dialog koennte im Hintergrund sein (Taskleiste pruefen) |
| "Nicht gefunden" | PrezioImager.exe muss im gleichen Ordner wie PrezioHub.exe liegen |

### Tools nicht gefunden

Alle `.exe`-Dateien muessen im gleichen Verzeichnis liegen:

```
PrezioHub/
  PrezioHub.exe
  PrezioImager.exe
  PrezioRecorder.exe
  PrezioDummy.exe
  docs/
    ...
```

---

## Updates

### Hub Auto-Update (beim Start)

PrezioHub prueft beim Start automatisch, ob eine neuere Version auf GitHub verfuegbar ist. Falls ja, erscheint oben im Fenster ein gruener Banner:

> **Update verfuegbar: v1.1.0 - Jetzt herunterladen**

1. Auf **"Jetzt herunterladen"** klicken
2. Speicherort waehlen (z.B. Desktop)
3. PrezioHub fragt, ob der Installer gestartet werden soll
4. Falls ja: Installer startet, PrezioHub schliesst sich
5. Installation durchfuehren (ueberschreibt die alte Version)

**Voraussetzung:** Internetverbindung (nicht ueber das Pi-WiFi, sondern normales Netzwerk).

### Pi-Firmware-Update (Tab "Pi-Steuerung")

Im Tab "Pi-Steuerung" gibt es den Abschnitt **FIRMWARE-UPDATE**:

1. Mit WiFi "Prezio-Recorder" verbinden
2. **"Pi-Firmware pruefen"** klicken
3. PrezioHub fragt die aktuelle Pi-Version ab und vergleicht mit GitHub
4. Falls ein Update verfuegbar ist: Changelog wird angezeigt + Button **"Jetzt updaten"**
5. Klick auf "Jetzt updaten":
   - Die neue `pi_recorder.py` wird von GitHub heruntergeladen
   - Per SFTP auf den Pi hochgeladen
   - Der Service `prezio-recorder` wird automatisch neugestartet
6. Bestaetigung wird angezeigt

**Voraussetzung:** PC muss mit WiFi "Prezio-Recorder" verbunden sein UND Internetzugang haben (z.B. ueber Ethernet oder mobilen Hotspot parallel zum Pi-WiFi).

---

## Fuer Entwickler

### Neues Update veroeffentlichen (GitHub Release)

So wird ein Update fuer alle PrezioHubs und Raspberry Pis veroeffentlicht:

```
1. Code aendern (z.B. pi_recorder.py, prezio_hub.py)
2. VERSION erhoehen in den geaenderten Dateien:
   - prezio_hub/prezio_hub.py:       VERSION = "1.1.0"
   - pi_recorder/pi_recorder.py:     VERSION = "1.1.0"
   - pi_recorder/prezio_imager.py:   VERSION = "1.1.0"  (optional)
   - prezio_hub/version_info.py:     filevers/prodvers anpassen
   - prezio_hub/prezio_installer.iss: MyAppVersion anpassen
3. git add . && git commit -m "v1.1.0 - Beschreibung" && git push
4. python build_all.py              (baut alle .exe Dateien)
5. Inno Setup kompilieren           (erzeugt PrezioHub_Setup_1.1.0.exe)
6. Auf GitHub ein Release erstellen:
   a) Repository -> Releases -> "Create a new release"
   b) Tag: v1.1.0  (muss zu VERSION im Code passen!)
   c) Titel: v1.1.0 - Beschreibung der Aenderungen
   d) Beschreibung/Changelog eintragen
   e) PrezioHub_Setup_1.1.0.exe als Asset hochladen
   f) "Publish release" klicken
```

**Was dann passiert:**
- Jeder PrezioHub prueft beim Start die GitHub API und sieht das neue Release
- Hub-Update: Gruener Banner erscheint -> User kann Installer herunterladen
- Pi-Update: "Pi-Firmware pruefen" erkennt die neue Version -> 1-Klick-Update auf den Pi

**Wichtig:**
- Ein einfacher `git push` reicht NICHT - es muss ein GitHub Release mit Tag erstellt werden
- Der Tag (z.B. `v1.1.0`) muss exakt zur `VERSION` Konstante im Code passen
- Fuer Hub-Updates muss die Setup-EXE als Release-Asset hochgeladen werden
- Pi-Updates funktionieren automatisch aus dem Release-ZIP (kein separates Asset noetig)

### Quellcode-Struktur

```
prezio_hub/
  prezio_hub.py          # Hauptanwendung (Tkinter)
  prezio_hub.ico         # Anwendungs-Icon
  build_all.py           # Baut alle .exe-Dateien
  prezio_installer.iss   # Inno Setup Installer-Script
  version_info.py        # Windows-Versionsinformationen
```

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
4. Ergebnis: `installer_output/PrezioHub_Setup_1.0.0.exe`

---

*Stand: Maerz 2026 - Soleco AG*
