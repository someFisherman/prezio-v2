# Prezio v2 - Vollstaendige Dokumentation

**Version:** 2.4.0  
**Stand:** Maerz 2026  
**Entwickelt fuer:** Soleco AG / Lehmann 2000, Zofingen  
**Plattformen:** iOS, Android (Flutter)  
**Repository:** https://github.com/someFisherman/prezio-v2.git

---

## Inhaltsverzeichnis

1. [Uebersicht](#1-uebersicht)
2. [Systemarchitektur](#2-systemarchitektur)
3. [Flutter-App (Smartphone)](#3-flutter-app-smartphone)
4. [Prezio Recorder (Raspberry Pi)](#4-prezio-recorder-raspberry-pi)
5. [Neues Geraet bauen (Pi Zero 2 W)](#5-neues-geraet-bauen-pi-zero-2-w)
6. [Supabase Cloud-Speicher](#6-supabase-cloud-speicher)
7. [PrezioHub (Windows-Dashboard)](#7-preziohub-windows-dashboard)
8. [Installer & Distribution](#8-installer--distribution)
9. [Validierungslogik](#9-validierungslogik)
10. [Dateistruktur & Code-Referenz](#10-dateistruktur--code-referenz)
11. [Ablauf (End-to-End)](#11-ablauf-end-to-end)
12. [Fehlerbehebung](#12-fehlerbehebung)
13. [Branding & Logos](#13-branding--logos)
14. [Cursor-Kontext (Prompt fuer neuen Chat)](#14-cursor-kontext-prompt-fuer-neuen-chat)

---

## 1. Uebersicht

Prezio ist eine Druckpruefungs-App fuer die Sanitaerbranche. Ein Monteur schliesst einen KELLER LEO5 Drucksensor an eine Leitung an, der Sensor ist per USB-Seriell mit einem **Prezio Recorder** (Raspberry Pi) verbunden. Die App auf dem Smartphone steuert die Aufzeichnung ueber WiFi, laedt die Messdaten, validiert automatisch ob die Leitung dicht ist, erstellt ein PDF-Protokoll mit Unterschrift und laedt alles automatisch nach **Supabase** hoch (kostenlos, keine Kreditkarte).

### Kernprinzipien

- **Kein Login**: Die App wird durch Verbindung mit dem Prezio Recorder freigeschaltet (Secret Key ueber WiFi)
- **Keine manuelle Manipulation**: PN (Betriebsdruck) und Medium (Luft/Wasser) werden bei Aufzeichnungsstart festgelegt und koennen nachtraeglich nicht geaendert werden
- **Automatische Validierung**: Das System entscheidet ob die Messung gueltig ist, nicht der Monteur
- **Automatische Ablage**: Protokolle werden ohne Benutzerinteraktion in Supabase hochgeladen
- **Wetterdaten-Korrektur**: Aussentemperaturschwankungen werden bei der Toleranzberechnung beruecksichtigt
- **Standort-Erkennung**: GPS + Nominatim (OpenStreetMap) fuer automatische und editierbare Ortsangabe

---

## 2. Systemarchitektur

```
┌──────────────────────┐     WiFi AP (192.168.4.1)     ┌──────────────────────┐
│                      │◄──────────────────────────────►│                      │
│   Prezio Recorder    │     HTTP REST API :8080        │   iPhone / Android   │
│   (Pi 4B / Zero 2 W) │                                │   Flutter App        │
│                      │                                │                      │
│   - WiFi Access Point│                                │   - Auth via Key     │
│   - KELLER LEO5      │                                │   - Aufzeichnung     │
│   - pi_recorder.py   │                                │     starten/stoppen  │
│   - CSV-Speicherung  │                                │   - CSV laden        │
│   - Secret Key       │                                │   - Auto-Validierung │
│   - HTTP API         │                                │   - PDF erstellen    │
│                      │                                │   - Supabase Upload  │
└────────┬─────────────┘                                └──────────┬───────────┘
         │ USB-Seriell                                             │ HTTPS
    ┌────┴─────┐                                          ┌────────┴────────┐
    │ KELLER   │                                          │  Supabase       │
    │ LEO5     │                                          │  (Postgres DB + │
    │ Sensor   │                                          │   File Storage) │
    └──────────┘                                          └─────────────────┘
                                                                   │
                                                          ┌────────┴────────┐
                                                          │  Open-Meteo     │
                                                          │  (Wetter-API)   │
                                                          └─────────────────┘
                                                                   │
                                                          ┌────────┴────────┐
                                                          │  Nominatim      │
                                                          │  (Standort)     │
                                                          └─────────────────┘
```

### Kommunikation

| Verbindung | Protokoll | Details |
|---|---|---|
| Recorder ↔ Sensor | USB-Seriell (9600 Baud) | KELLER Protokoll (CRC16), Adresse 1 |
| Recorder ↔ Smartphone | HTTP REST API | WiFi AP "Prezio-Recorder", IP 192.168.4.1:8080 |
| Smartphone ↔ Supabase | HTTPS REST API | Anon Key, kein Login noetig |
| Smartphone ↔ Wetter-API | HTTPS | Open-Meteo (kostenlos, kein Key) |
| Smartphone ↔ Nominatim | HTTPS | OpenStreetMap (kostenlos, kein Key) |

---

## 3. Flutter-App (Smartphone)

### Technologie-Stack

- **Framework:** Flutter (Dart), SDK ^3.9.2
- **State Management:** Riverpod 2.6
- **Charts:** fl_chart
- **PDF:** pdf + printing
- **Signature:** signature 5.5
- **HTTP:** http (fuer Recorder-API, Supabase, Wetter, Nominatim)
- **GPS:** geolocator (fuer Standort + Wetterdaten)
- **Crypto:** crypto (SHA-256 fuer CSV-Integritaet)
- **Cloud:** Supabase (reine REST API, kein SDK)

### Screen-Flow

```
ConnectScreen (Kolibri-Logo, Recorder-Verbindung + Key-Auth)
  └── RecorderScreen (Aufzeichnung starten/stoppen)
        ├── [Aufzeichnung stoppen] → InternetCheckScreen
        └── [Aufzeichnungen] → RecorderFileSelectionScreen (Messung waehlen)
                                    └── InternetCheckScreen
                                          └── ProtocolFormScreen (Projekt-Info, Standort,
                                          │     Auto-Validierung, Wetter, Druckkurve)
                                          └── SignatureScreen (Unterschrift + Chart)
                                                └── SendProtocolScreen (Speichern + Supabase)
```

**Wichtige Screens:**

| Screen | Datei | Funktion |
|---|---|---|
| ConnectScreen | `connect_screen.dart` | Einstieg: Kolibri-Logo, pollt Recorder, holt Key |
| RecorderScreen | `recorder_screen.dart` | Aufzeichnung starten/stoppen, "Aufzeichnungen"-Button |
| RecorderFileSelectionScreen | `recorder_file_selection_screen.dart` | Einzelauswahl einer Messung vom Recorder |
| InternetCheckScreen | `internet_check_screen.dart` | WLAN-Aus-Befehl an Recorder, Internet pruefen, fruehen CSV-Upload |
| ProtocolFormScreen | `protocol_form_screen.dart` | Formular mit Standort (Nominatim), Wetter, Validierung, Druckkurve |
| SignatureScreen | `signature_screen.dart` | Unterschrift + Chart-Vorschau |
| SendProtocolScreen | `send_protocol_screen.dart` | Lokal speichern + Supabase Upload |
| SettingsScreen | `settings_screen.dart` | Recorder-IP, Climartis-Logo |

### Authentifizierung

Es gibt **kein Login und kein Passwort**. Der Zugang zur App funktioniert so:

1. App startet → ConnectScreen zeigt Kolibri-Logo
2. Benutzer verbindet Handy mit WiFi "Prezio-Recorder"
3. App pollt automatisch `/health` auf 192.168.4.1:8080
4. Bei Erfolg: App ruft `/auth/key` ab → erhaelt Secret Key
5. Key wird validiert → Zugang zum RecorderScreen

Der Key wird bei jedem App-Start neu geholt. Ohne Recorder kein Zugang.

### Wichtige Services

| Service | Datei | Aufgabe |
|---|---|---|
| RecorderConnectionService | `recorder_connection_service.dart` | HTTP-Client fuer Recorder-API inkl. Key + WLAN-Aus |
| MeasurementService | `measurement_service.dart` | Messungen laden, verwalten, exportieren |
| CsvParserService | `csv_parser_service.dart` | CSV parsen (inkl. Metadaten-Header) |
| ValidationService | `validation_service.dart` | Druckpruefung validieren |
| WeatherService | `weather_service.dart` | Wetterdaten von Open-Meteo holen |
| NominatimService | `nominatim_service.dart` | Reverse Geocoding + Ortssuche (OpenStreetMap) |
| SupabaseUploadService | `supabase_upload_service.dart` | REST-Upload zu Supabase (Tabellen + Storage) |
| PdfGeneratorService | `pdf_generator_service.dart` | A4-PDF: Seite 1 Protokoll + Unterschriften, Seite 2 nur Druckkurve |
| ProtocolStorageService | `protocol_storage_service.dart` | Lokale Ordnerstruktur + Metadaten |
| StorageService | `storage_service.dart` | SharedPreferences (Einstellungen) |

### Datenmodelle

| Modell | Datei | Felder |
|---|---|---|
| Sample | `sample.dart` | index, timestamp, timestampUtc, pressureBar, temperatureC, pressureRounded, temperatureRounded |
| Measurement | `measurement.dart` | id, filename, startTime, endTime, duration, samples[], validationStatus, metadata |
| CsvMetadata | `measurement.dart` | name, pn, medium, intervalS |
| ProtocolData | `protocol_data.dart` | measurement, objectName, projectName, author, nominalPressure, testMedium, testPressure, result, passed, technicianName, signature, chartImage, notes, location, latitude, longitude, **testProfileId, testProfileName, detectedHoldDurationHours, pressureDropBar, failureReasons** |
| TestMedium | `protocol_data.dart` | air (Faktor 1.1), water (Faktor 1.5) |
| TestProfile | `test_profile.dart` | id, name, medium, holdDurationHours, maxPressureDropBar, etc. |
| WeatherData | `weather_data.dart` | outdoorTempStart, outdoorTempEnd, minTemp, maxTemp, tempSwing, additionalTolerance |

### CSV-Format (vom Recorder)

```csv
# Name: Heizung OG
# PN: 25
# Medium: air
# Interval: 10.0
No,Datetime,Datetime_UTC,P1_bar,TOB1_C,P1_bar_rounded,TOB1_C_rounded
1,15.03.2026 10:00:00,2026-03-15T09:00:00Z,3.14159,21.3456,3.14,21.35
2,15.03.2026 10:00:10,2026-03-15T09:00:10Z,3.14201,21.3501,3.14,21.35
...
```

Die `#`-Zeilen enthalten Metadaten die bei Aufzeichnungsstart festgelegt werden. PN und Medium sind danach gesperrt (Anti-Manipulation).

---

## 4. Prezio Recorder (Raspberry Pi)

### Hardware

- **Raspberry Pi 4 B** (Entwicklung/Test) oder **Pi Zero 2 W** (Produktion)
- **32 GB microSD** (reicht fuer ~10 Messungen a 24h bei 10s Intervall ≈ 8.6 MB gesamt)
- **KELLER LEO5 Drucksensor** angeschlossen per USB-Seriell-Adapter
- **USB-Netzteil** (5V, mind. 2.5A fuer Pi 4, 1A fuer Pi Zero 2 W)

### Software

- **Raspberry Pi OS Lite (64-bit) - Bookworm**
- **Python 3** mit `pyserial`
- **NetworkManager** (nmcli) fuer WiFi Access Point
- **systemd** fuer Auto-Start

### Recorder Script (`pi_recorder.py`)

Headless Python-Script das:
1. Den KELLER LEO5 Sensor per USB-Seriell (9600 Baud) anspricht
2. Messwerte (Druck P1, Temperatur TOB1) in 10-Sekunden-Zyklen aufzeichnet
3. CSV-Dateien mit Metadaten-Headern in `./data/` speichert
4. Eine HTTP REST API auf Port 8080 bereitstellt
5. Einen **Secret Key** generiert und speichert (`/home/pi/prezio_key.txt`)
6. Maximal **10 Messungen** speichert (aelteste wird automatisch geloescht)

### API-Endpunkte

| Methode | Pfad | Beschreibung |
|---|---|---|
| `GET` | `/` | Status-Meldung "Prezio Recorder - HTTP API running" |
| `GET` | `/health` | Sensor-Status, Seriennummer, Verbindung |
| `GET` | `/auth/key` | Secret Key abrufen (App-Authentifizierung) |
| `GET` | `/files` | Liste aller CSV-Dateien (Name, Groesse, Datum) |
| `GET` | `/files/{name}` | CSV-Datei herunterladen |
| `DELETE` | `/files/{name}` | CSV-Datei loeschen |
| `POST` | `/recording/start` | Aufzeichnung starten (JSON: name, pn, medium, interval_s) |
| `POST` | `/recording/stop` | Aufzeichnung stoppen |
| `GET` | `/recording/status` | Status (laeuft?, Name, Dauer, Samples, letzte Werte) |
| `POST` | `/wifi/off` | WLAN AP fuer 120s ausschalten, dann automatisch wieder starten |
| `POST` | `/reboot` | Recorder neustarten (1s Verzoegerung, dann `sudo reboot`) |

### Secret Key

Der Recorder generiert beim ersten Start automatisch einen Key:
- SHA-256 Hash von "Prezio-Recorder-2026"
- Gespeichert in `/home/pi/prezio_key.txt`
- Wird ueber `/auth/key` an die App ausgeliefert
- Die App prueft den Key bei jeder Verbindung

### WiFi Access Point

| Einstellung | Wert |
|---|---|
| SSID | `Prezio-Recorder` |
| Passwort | `prezio2026` |
| IP-Adresse | `192.168.4.1` |
| Modus | WPA-PSK, 2.4 GHz, Kanal 7 |
| DHCP | Automatisch via NetworkManager "shared" |

### Konfiguration (`pi_recorder.py`)

```python
DATA_DIR = "./data"        # Speicherort fuer CSV-Dateien
HTTP_PORT = 8080           # API-Port
DEFAULT_INTERVAL_S = 10    # Standard-Messintervall
MAX_FILES = 10             # Maximale Anzahl gespeicherter Messungen
SENSOR_BAUD = 9600         # Baudrate fuer KELLER Sensor
SENSOR_ADDRESS = 1         # Modbus-Adresse des Sensors
```

---

## 5. Neues Geraet bauen (Pi Zero 2 W)

### Einkaufsliste

| Teil | Preis ca. | Link/Hinweis |
|---|---|---|
| Raspberry Pi Zero 2 W | CHF 20 | pi-shop.ch oder digitec.ch |
| microSD 32 GB (Class 10) | CHF 10 | SanDisk Ultra empfohlen |
| USB-OTG-Adapter (Micro-USB auf USB-A) | CHF 5 | Fuer den USB-Seriell-Adapter |
| USB-Seriell-Adapter (RS485 / TTL) | CHF 15 | Muss zum KELLER LEO5 passen |
| Micro-USB-Netzteil (5V / 2A) | CHF 15 | Offizielles Pi-Netzteil empfohlen |
| Gehaeuse (optional) | CHF 10 | 3D-Druck oder Standardgehaeuse |
| **KELLER LEO5 Drucksensor** | vorhanden | USB-Seriell-Anschluss |

### Methode 1: PrezioImager (empfohlen - vollautomatisch)

Der PrezioImager flasht die SD-Karte und richtet den Pi komplett automatisch ein. Kein SSH, kein manuelles Setup, kein Terminal noetig.

#### Ablauf

1. **PrezioImager starten** (aus PrezioHub > Tools, oder direkt die .exe)
   - Benoetigt Admin-Rechte (UAC-Dialog bestaetigen)
   - PrezioImager laedt beim Start die neueste Firmware von GitHub (oder nutzt den Cache)
2. **SD-Karte einlegen** und im PrezioImager auswaehlen
   - **Achtung:** Alle Daten auf der Karte werden geloescht!
3. **"Flash starten"** klicken
   - Raspberry Pi OS wird automatisch heruntergeladen (beim ersten Mal, ~500 MB)
   - Karte wird formatiert und geflasht
   - `pi_recorder.py`, `setup_pi.sh`, `requirements.txt`, `howto.txt` und `pyserial` werden auf die Karte kopiert
   - Ein Erststart-Script (`firstrun.sh`) wird erstellt
4. **SD-Karte in den Pi einsetzen und Strom anschliessen**
5. **3-5 Minuten warten** (der Pi durchlaeuft einen 2-Phasen-Boot, siehe unten)
6. WiFi "Prezio-Recorder" sollte sichtbar sein

#### 2-Phasen-Boot (was im Hintergrund passiert)

| Phase | Was passiert | Dauer |
|-------|-------------|-------|
| **Phase 1** (erster Boot) | User `pi` wird erstellt, SSH aktiviert, Firmware-Dateien nach `/home/pi/prezio-v2/pi_recorder` kopiert, systemd-Service `prezio-setup` fuer Phase 2 erstellt, **dann automatischer Reboot** | ~60s |
| **Phase 2** (zweiter Boot) | `prezio-setup.service` startet `setup_pi.sh`: WiFi-Country auf CH gesetzt, `rfkill unblock wifi`, NetworkManager wartet, WiFi AP "Prezio-Recorder" konfiguriert, Python venv + pyserial installiert, Recorder-Service installiert und gestartet. Service entfernt sich danach selbst. | ~60-120s |

Der Pi ist nach Phase 2 komplett einsatzbereit. Es muss nichts manuell gemacht werden.

#### Firmware-Cache im Imager

- Der Imager versucht beim Start die neuesten Dateien von GitHub zu laden
- Falls kein Internet: lokaler Cache wird genutzt (max. 24h alt)
- Falls kein Internet UND Cache aelter als 24h: Fehlermeldung - Imager muss mit Internet gestartet werden
- Cache-Pfad: `%LOCALAPPDATA%\PrezioHub\firmware_cache\`

### Methode 2: Manuelle Einrichtung (Fallback)

Falls der PrezioImager nicht verfuegbar ist oder etwas schief geht.

#### 1. SD-Karte mit Raspberry Pi Imager vorbereiten

1. **Raspberry Pi Imager** herunterladen: https://www.raspberrypi.com/software/
2. Imager starten:
   - **Geraet:** Raspberry Pi Zero 2 W (oder Pi 4)
   - **OS:** "Raspberry Pi OS Lite (64-bit)" (unter "Raspberry Pi OS (other)")
   - **Speicher:** 32 GB microSD
3. **Vor dem Schreiben** → Zahnrad-Icon / "Einstellungen bearbeiten":
   - Hostname: `prezio-recorder`
   - SSH aktivieren: Ja, mit Passwort
   - Benutzername: `pi`
   - Passwort: `Prezio2000!`
   - **WLAN konfigurieren:** Dein Buero-/Heim-WiFi eintragen (fuer Ersteinrichtung!)
   - Zeitzone: `Europe/Zurich`
4. "Schreiben" klicken und warten

#### 2. Ersteinrichtung per SSH

1. SD-Karte in den Pi einsetzen, Strom anschliessen, ~60 Sekunden warten
2. Auf dem PC (PowerShell):

```bash
ssh pi@prezio-recorder.local
```

Falls `prezio-recorder.local` nicht gefunden wird: IP im Router nachschauen.

3. Software installieren:

```bash
sudo apt update && sudo apt install -y git python3-pip python3-venv
cd /home/pi
git clone https://github.com/someFisherman/prezio-v2.git
cd prezio-v2/pi_recorder
sudo bash setup_pi.sh
```

4. Neustart:

```bash
sudo reboot
```

5. Testen: WiFi "Prezio-Recorder" suchen, verbinden (Passwort: `prezio2026`), im Browser `http://192.168.4.1:8080/health` oeffnen.

### Pi zusammenbauen

1. microSD in den Pi Zero 2 W einsetzen
2. USB-OTG-Adapter an den **Daten-Micro-USB** (nicht Power!) anschliessen
3. USB-Seriell-Adapter mit KELLER LEO5 verbinden
4. USB-Seriell-Adapter an den OTG-Adapter stecken
5. Micro-USB-Netzteil an den **Power-Port** anschliessen

**WICHTIG beim Pi Zero 2 W:** Es gibt zwei Micro-USB-Ports!
- Links (aussen): **Power** (nur Strom)
- Rechts (innen, neben HDMI): **Daten** (hier den OTG-Adapter anschliessen)

### Unterschiede Pi 4 B vs Pi Zero 2 W

| Eigenschaft | Pi 4 B | Pi Zero 2 W |
|---|---|---|
| USB-Ports | 4x USB-A | 1x Micro-USB (OTG) |
| WiFi | 2.4 + 5 GHz | 2.4 GHz |
| RAM | 1-8 GB | 512 MB |
| Leistung | Mehr als genug | Voellig ausreichend |
| Stromverbrauch | ~3-7W | ~1-2W |
| Preis | ~CHF 50-80 | ~CHF 20 |
| OTG-Adapter noetig? | Nein | Ja |
| PrezioImager | Funktioniert | Funktioniert |
| Setup-Skript | Identisch | Identisch |

Sowohl PrezioImager als auch `setup_pi.sh` funktionieren identisch auf beiden Modellen.

### Mehrere Geraete

Jedes Geraet ist unabhaengig. Bei mehreren Geraeten:
- Jeder Pi hat die gleiche SSID ("Prezio-Recorder") und IP (192.168.4.1)
- Das Handy verbindet sich immer nur mit dem Pi der gerade in Reichweite ist
- Kein Konflikt, da nie zwei Pis gleichzeitig in Reichweite sein sollten
- Falls doch: SSID anpassen per SSH mit `sudo bash setup_pi.sh "Prezio-Geraet-2"`

---

## 6. Supabase Cloud-Speicher

### Warum Supabase?

- **Komplett kostenlos** (Free Tier: 500 MB Datenbank, 1 GB Storage)
- **Keine Kreditkarte** noetig
- **Kein Login am Handy** - alles fix hinterlegt mit Anon Key
- **Buero-Zugang** ueber das Supabase Dashboard (Web-Browser)
- **Kein SDK** noetig - reine HTTP REST API mit dem `http` Paket

### Projekt-Daten

| Einstellung | Wert |
|---|---|
| Supabase URL | `https://ndqisdqdhzeenvjkkuxd.supabase.co` |
| Anon Key | In `lib/config/supabase_config.dart` hinterlegt |
| Storage Bucket | `protokolle` |
| Region | Central EU |

### Datenbank-Tabellen

#### Tabelle `rohdaten` (fruehe CSV-Uploads)

Wird sofort hochgeladen sobald das Handy Internet hat (vor dem Protokoll).

| Spalte | Typ | Beschreibung |
|---|---|---|
| `id` | int8 (PK) | Auto-Increment |
| `created_at` | timestamptz | Zeitstempel (default: now()) |
| `name` | text | Messungsname (vom Monteur) |
| `csv` | text | Kompletter CSV-Inhalt |
| `csv_sha256` | text | SHA-256 Hash (Integritaet) |

#### Tabelle `protokolle` (fertige Protokolle)

Wird nach dem vollstaendigen Protokoll-Flow hochgeladen.

| Spalte | Typ | Beschreibung |
|---|---|---|
| `id` | int8 (PK) | Auto-Increment |
| `created_at` | timestamptz | Zeitstempel |
| `folder_name` | text | Ordnername (fuer Storage-Referenz) |
| `version` | text | App-Version |
| `object_name` | text | Objekt / Anlage |
| `project` | text | Projektname |
| `author` | text | Verfasser |
| `technician` | text | Monteurname |
| `location` | text | Standort (Adresse) |
| `latitude` | float8 | GPS Breitengrad |
| `longitude` | float8 | GPS Laengengrad |
| `measurement_filename` | text | CSV-Dateiname |
| `start_time` | text | Messbeginn (ISO 8601) |
| `end_time` | text | Messende (ISO 8601) |
| `duration_seconds` | int8 | Messdauer in Sekunden |
| `sample_count` | int8 | Anzahl Messpunkte |
| `nominal_pressure` | float8 | Nenndruck (PN) |
| `test_medium` | text | Pruefmedium (air/water) |
| `test_pressure` | float8 | Pruefdruck (bar) |
| `passed` | bool | Pruefung bestanden? |
| `result` | text | Ergebnis-Text |
| `validation_reason` | text | Begruendung |
| `csv_sha256` | text | CSV-Hash |
| `pdf_path` | text | Pfad zum PDF in Storage |

**RLS (Row Level Security) ist auf beiden Tabellen deaktiviert** - der Anon Key hat vollen Zugriff.

### Storage Bucket `protokolle`

Hier werden die echten Dateien (PDFs + CSVs) gespeichert. Dateinamen enthalten einen Timestamp zur Eindeutigkeit:

```
protokolle/
├── Heizung_OG_1739520123456/
│   ├── protokoll_1739520123456.pdf
│   └── messdaten_1739520123456.csv
├── Badezimmer_EG_1739520789012/
│   ├── protokoll_1739520789012.pdf
│   └── messdaten_1739520789012.csv
```

### Upload-Ablauf

1. **Frueh-Upload** (InternetCheckScreen): Sobald Internet vorhanden → CSV als Text in `rohdaten`-Tabelle
2. **Protokoll-Upload** (SendProtocolScreen): Nach Unterschrift → PDF + CSV in Storage + Metadaten in `protokolle`-Tabelle

### Buero-Zugriff

Das Buero greift ueber https://supabase.com/dashboard auf die Daten zu:
- **Table Editor**: Alle Protokolle als Tabelle sehen, filtern, sortieren
- **Storage**: PDFs und CSVs direkt herunterladen
- **SQL Editor**: Eigene Abfragen (z.B. "Alle fehlgeschlagenen Pruefungen")

### Neues Supabase-Projekt einrichten (falls noetig)

1. https://supabase.com → Konto erstellen (GitHub oder E-Mail, keine Kreditkarte)
2. "New Project" → Name, Region (Central EU), Passwort
3. **Project Settings > API**: URL + Anon Key kopieren
4. In `lib/config/supabase_config.dart` eintragen
5. **Table Editor**: Tabellen `rohdaten` und `protokolle` erstellen (Spalten siehe oben)
6. **RLS abschalten** auf beiden Tabellen
7. **Storage**: Bucket `protokolle` erstellen

---

## 7. PrezioHub (Windows-Dashboard)

PrezioHub ist die zentrale Steuerungsoberflaeche fuer Techniker und Entwickler. Es buendelt alle Werkzeuge, Pi-Fernsteuerung, Firmware-Updates, Supabase-Zugriff und Dokumentationen in einer Desktop-Anwendung.

### Tabs

| Tab | Funktion |
|-----|----------|
| **Dashboard** | Live-Status des Pi (Verbindung, Sensor, Live-Werte P1/TOB1). Oranges Banner bei veraltetem Pi. Rotes Banner bei fehlendem Internet/Cache. Auto-Refresh alle 5s. |
| **Pi-Steuerung** | SSH oeffnen, Service neustarten, Pi rebooten, WiFi aus (120s), **Firmware-Update** (Pi-Version pruefen + per SFTP updaten), Service-Logs laden |
| **Aufzeichnung** | Fernsteuerung: Aufzeichnung starten/stoppen, Status anzeigen |
| **Tools** | PrezioImager, PC Recorder und Dummy Server starten |
| **Supabase** | Protokoll-Ordner aus Supabase Storage laden, nach Datum sortiert (neueste oben), Dateien/Ordner als ZIP herunterladen |
| **Dokumentation** | Alle Projekt-Dokumentationen oeffnen |

### Firmware-Cache

PrezioHub laedt beim Start automatisch folgende Dateien von GitHub (`main`-Branch) herunter:

- `pi_recorder.py`
- `setup_pi.sh`
- `requirements.txt`
- `howto.txt`

Diese werden unter `%LOCALAPPDATA%\PrezioHub\firmware_cache\` gespeichert. Der Cache wird bei jedem Start mit Internet ueberschrieben. Ohne Internet wird der bestehende Cache verwendet (rotes Banner im Dashboard). Der Cache wird sowohl vom Hub (Pi-Updates per SFTP) als auch vom PrezioImager (SD-Karten flashen) genutzt.

**GitHub-Quelle:** `https://raw.githubusercontent.com/someFisherman/prezio-v2/main/pi_recorder/`

### Pi-Firmware-Update (Ablauf)

1. Hub vergleicht `VERSION` der gecachten `pi_recorder.py` mit der Pi-Version (aus `/health`)
2. Falls Pi veraltet: Oranges Banner "UPDATE FAELLIG" im Dashboard + "Jetzt updaten" Button in Pi-Steuerung
3. Update per SFTP: Gecachte `pi_recorder.py` wird auf den Pi hochgeladen (`/home/pi/prezio-v2/pi_recorder/`)
4. Service `prezio-recorder` wird per SSH neugestartet
5. **Kein Internet auf dem Pi noetig** - alles geht ueber das Pi-WiFi

### Technik

- **Framework:** Python 3 / Tkinter
- **SSH/SFTP:** paramiko (im Hub eingebaut)
- **Kommunikation:** HTTP REST API zum Pi (Port 8080)
- **Netzwerk:** PC muss mit WiFi "Prezio-Recorder" verbunden sein
- **Quellcode:** `prezio_hub/prezio_hub.py`

### Enthaltene Tools (als .exe)

| Executable | Beschreibung | Admin noetig? |
|-----------|-------------|---------------|
| `PrezioHub.exe` | Zentrale Steuerung + Firmware-Updates | Nein |
| `PrezioImager.exe` | SD-Karten Flash Tool (vollautomatisch) | Ja (UAC) |
| `PrezioRecorder.exe` | Windows-Sensor-Recorder | Nein |
| `PrezioDummy.exe` | Mock-Server (Konsolenfenster) | Nein |

---

## 8. Installer & Distribution

### Uebersicht

Alle Windows-Werkzeuge werden als eigenstaendige `.exe`-Dateien mit PyInstaller gebaut. Der Installer wird mit Inno Setup erstellt. Endbenutzer brauchen kein Python.

### Build-Prozess

```
1. python build_all.py          → Baut alle 4 .exe + kopiert Dokumentation
2. Inno Setup kompilieren       → Erzeugt PrezioHub_Setup_X.X.X.exe
```

### Distribution bauen

```bash
cd prezio_v2/prezio_hub
python build_all.py
```

Erzeugt `dist/PrezioHub/` mit:
- 4 Executables (PrezioHub, PrezioImager, PrezioRecorder, PrezioDummy)
- `docs/` Ordner mit allen Dokumentationen (umbenannt fuer Lesbarkeit)

### Installer erstellen

1. **Inno Setup** installieren: https://jrsoftware.org/isdl.php
2. `prezio_hub/prezio_installer.iss` oeffnen
3. "Compile" klicken
4. Ergebnis: `installer_output/PrezioHub_Setup_X.X.X.exe`

### Was der Installer macht

- Installiert nach `C:\Program Files\PrezioHub`
- Erstellt Startmenue-Eintraege (Soleco AG > PrezioHub)
- Optionale Desktop-Verknuepfungen
- Saubere Deinstallation ueber Windows "Apps & Features"
- Kein Python oder andere Abhaengigkeiten noetig

### Versionierung

| Datei | Konstante | Verwendung |
|-------|-----------|------------|
| `pi_recorder/pi_recorder.py` | `VERSION = "1.1.0"` | Pi-Firmware-Version, wird ueber `/health` zurueckgegeben |
| `prezio_hub/prezio_hub.py` | `VERSION = "1.1.0"` | Nur informativ (kein Auto-Update fuer Hub) |
| `pi_recorder/prezio_imager.py` | `VERSION = "1.1.0"` | Nur informativ |
| `prezio_hub/version_info.py` | `filevers=(1,1,0,0)` | Windows-Dateiinfos der EXE |
| `prezio_hub/prezio_installer.iss` | `MyAppVersion "1.1.0"` | Installer-Versionsnummer |

**Wichtig:** Nur die `VERSION` in `pi_recorder.py` ist relevant fuer das Update-System. Der Hub liest diese aus der gecachten Datei und vergleicht sie mit der Version auf dem Pi.

### Update-System

Das Update-System ist bewusst einfach gehalten:

#### Pi-Firmware-Update (automatisch)

Der Hub und der Imager ziehen `pi_recorder.py`, `setup_pi.sh`, `requirements.txt` und `howto.txt` direkt vom `main`-Branch auf GitHub. **Kein GitHub Release noetig**, ein einfacher `git push` genuegt.

**Ablauf fuer Entwickler:**
1. `pi_recorder.py` aendern (z.B. Bugfix, neue Funktion)
2. `VERSION = "1.2.0"` in `pi_recorder.py` hochsetzen
3. `git add . && git commit -m "Pi Recorder v1.2.0" && git push`
4. Fertig - beim naechsten Start von Hub/Imager wird die neue Version gecacht

**Ablauf fuer Techniker (Pi updaten):**
1. PrezioHub mit Internet starten (Firmware-Cache wird aktualisiert)
2. Mit WiFi "Prezio-Recorder" verbinden
3. Dashboard zeigt oranges Banner "UPDATE FAELLIG: Pi vX.X.X → vY.Y.Y"
4. In Tab "Pi-Steuerung" → "Jetzt updaten" klicken
5. Gecachte `pi_recorder.py` wird per SFTP auf den Pi hochgeladen
6. Service wird automatisch neugestartet

**Ablauf fuer neue SD-Karten:**
- PrezioImager verwendet automatisch die gecachte Firmware
- Falls kein Internet: Cache wird genutzt (max. 24h alt, sonst Fehlermeldung)

#### Hub / Recorder / Dummy (manuell)

Diese Programme haben kein Auto-Update. Neues Update verteilen:
1. Code aendern, `VERSION` erhoehen
2. `python build_all.py`
3. Inno Setup kompilieren
4. Installer manuell verteilen

---

## 9. Validierungslogik

### Physikalisches Modell

Die Validierung prueft ob der Druckverlust waehrend der Testdauer innerhalb der erwarteten Grenzen liegt. Druckaenderungen koennen durch Temperatur verursacht werden (kein Leck) oder durch ein echtes Leck.

#### Luft (ideales Gasgesetz)

```
pErwartet = p0 × (T1 + 273.15) / (T0 + 273.15)
```

Wenn die Temperatur steigt, steigt auch der Druck (und umgekehrt). Das ist normal und kein Leck.

#### Wasser (thermische Ausdehnung)

```
pErwartet = p0 + 0.003 × p0 × (T1 - T0)
```

Wasser dehnt sich weniger stark aus als Luft.

### Toleranzberechnung

```
Basis-Toleranz = max(2% × Anfangsdruck, 0.1 bar)
```

#### Wetter-Anpassung

Wenn die Aussentemperatur waehrend der Messung stark schwankt (z.B. Tag/Nacht-Zyklus), koennen Teile der Leitung die nicht vom Sensor erfasst werden trotzdem temperaturbeeinflusst sein.

```
Wenn Aussen-Schwankung > 2°C:
  Zusatz-Toleranz = 0.3% × Schwankung × Anfangsdruck
  
Gesamt-Toleranz = Basis-Toleranz + Zusatz-Toleranz
```

Wetterdaten kommen von **Open-Meteo** (kostenlos, kein API-Key). Wenn kein Internet verfuegbar war, wird die Standard-Toleranz ohne Wetter-Anpassung verwendet.

### Pruefergebnis (Profil-basiert)

Die Validierung nutzt **TestProfile** (z.B. SIA 385/1 Wasser, Luft Standard) mit:
- Plateau-Erkennung (laengste Phase mit Druck >= Soll)
- Druckabfall: Start- vs. Enddruck (robust gegen Rauschen)
- Haltezeit, Datenluecken, max. Druckabfall

```
Wenn alle Kriterien erfuellt → BESTANDEN (kein Leck)
Sonst → NICHT BESTANDEN (failureReasons)
```

Profil wird automatisch aus Medium abgeleitet (Wasser → Wasser Standard, Luft → Luft Standard).

### Sicherheitsgrenze

Druck darf nie 1.5 × PN ueberschreiten. Falls doch → automatisch ungueltig.

### Pruefdruck-Faktoren

| Medium | Faktor | Beispiel PN 25 |
|---|---|---|
| Luft | 1.1 × PN | 27.5 bar |
| Wasser | 1.5 × PN | 37.5 bar |

### PN-Werte (Betriebsdruck)

Verfuegbar: 6, 10, 16, 20, 25, 32, 40, 50, 63, 80, 100 bar

---

## 10. Dateistruktur & Code-Referenz

```
prezio_v2/
├── lib/
│   ├── main.dart                          # App-Einstiegspunkt (kein Firebase mehr)
│   ├── app.dart                           # MaterialApp + Theme → ConnectScreen
│   │
│   ├── config/
│   │   └── supabase_config.dart           # Supabase URL + Anon Key + Bucket
│   │
│   ├── models/
│   │   ├── models.dart                    # Barrel-Export
│   │   ├── measurement.dart               # Measurement, CsvMetadata, ValidationStatus
│   │   ├── sample.dart                    # Sample (Einzelmesswert)
│   │   ├── protocol_data.dart             # ProtocolData, TestMedium
│   │   ├── test_profile.dart              # TestProfile (Validierungsprofile)
│   │   └── weather_data.dart             # WeatherData
│   │
│   ├── screens/
│   │   ├── screens.dart                   # Barrel-Export
│   │   ├── connect_screen.dart            # Einstieg: Kolibri, Recorder-Auth
│   │   ├── recorder_screen.dart           # Aufzeichnung starten/stoppen
│   │   ├── recorder_file_selection_screen.dart  # Messung vom Recorder waehlen
│   │   ├── internet_check_screen.dart     # Internet pruefen, Reboot, Frueh-Upload
│   │   ├── protocol_form_screen.dart      # Protokoll + Standort + Wetter + Kurve
│   │   ├── signature_screen.dart          # Unterschrift + Chart
│   │   ├── send_protocol_screen.dart      # Speichern + Supabase Upload
│   │   ├── measurement_list_screen.dart   # Alle geladenen Messungen
│   │   ├── measurement_detail_screen.dart # Messungsdetails + Chart
│   │   └── settings_screen.dart           # Recorder-IP, Climartis-Logo
│   │
│   ├── services/
│   │   ├── services.dart                  # Barrel-Export
│   │   ├── recorder_connection_service.dart  # HTTP-Client fuer Recorder + Key + Reboot
│   │   ├── measurement_service.dart       # Messungsverwaltung
│   │   ├── csv_parser_service.dart        # CSV parsen/generieren
│   │   ├── validation_service.dart        # Druckpruefung validieren
│   │   ├── weather_service.dart           # Open-Meteo Wetter-API
│   │   ├── nominatim_service.dart         # Reverse Geocoding + Ortssuche
│   │   ├── supabase_upload_service.dart   # REST-Upload zu Supabase
│   │   ├── pdf_generator_service.dart     # A4-PDF mit Lehmann-2000-Logo
│   │   ├── protocol_storage_service.dart  # Lokale Ordnerstruktur
│   │   ├── storage_service.dart           # SharedPreferences
│   │   └── email_service.dart             # E-Mail (Legacy, nicht aktiv)
│   │
│   ├── providers/
│   │   ├── providers.dart                 # Barrel-Export
│   │   └── app_providers.dart             # Riverpod-Provider
│   │
│   ├── widgets/
│   │   ├── widgets.dart                   # Barrel-Export
│   │   ├── pressure_chart.dart            # Druck/Temperatur-Chart (fl_chart, smooth)
│   │   └── measurement_card.dart          # Messungs-Karte
│   │
│   └── utils/
│       ├── utils.dart                     # Barrel-Export
│       ├── constants.dart                 # App-Konstanten, Recorder-Adresse
│       ├── formatters.dart                # Zahlen/Datum-Formatierung (de_CH)
│       └── theme.dart                     # Material Theme
│
├── pi_recorder/
│   ├── pi_recorder.py                     # Headless Python-Recorder + HTTP API + Key
│   ├── setup_pi.sh                        # Pi-Setup (WiFi AP, Service, Python)
│   ├── requirements.txt                   # pyserial>=3.5
│   ├── howto.txt                          # Aufbau-Anleitung (Kurzform)
│   └── data/                              # CSV-Dateien (zur Laufzeit erstellt)
│
├── pc_recorder/                           # PC-Version des Recorders (mit GUI)
│   ├── prezio_recorder.py                 # Hauptprogramm (Tkinter + HTTP-Server)
│   ├── start_recorder.bat                 # Startscript
│   └── requirements.txt                   # pyserial
│
├── dummy_server/                          # Test-Server fuer Entwicklung
│   ├── server.py                          # Mock-Server (simuliert Pi-API)
│   ├── start_server.bat                   # Startscript
│   └── data/                              # Beispiel-CSV-Dateien
│
├── prezio_hub/                            # PrezioHub Dashboard + Distribution
│   ├── prezio_hub.py                      # Zentrale Steuerungsoberflaeche (Tkinter)
│   ├── prezio_hub.ico                     # Anwendungs-Icon
│   ├── build_all.py                       # Baut alle 4 .exe mit PyInstaller
│   ├── prezio_installer.iss               # Inno Setup Installer-Script
│   ├── version_info.py                    # Windows-Versionsinformationen
│   └── dist/PrezioHub/                    # Fertige Distribution (nach Build)
│       ├── PrezioHub.exe
│       ├── PrezioImager.exe
│       ├── PrezioRecorder.exe
│       ├── PrezioDummy.exe
│       └── docs/                          # Dokumentationen (umbenannt)
│
├── assets/images/
│   ├── kolibri.png                        # App-Logo (Kolibri)
│   ├── lehmann2000.png                    # PDF-Logo (Lehmann 2000)
│   └── climartis.png                      # Mutterfirma-Logo (Settings)
├── ios/                                   # iOS-spezifisch
├── android/                               # Android-spezifisch
├── pubspec.yaml                           # Flutter-Abhaengigkeiten
├── DOKUMENTATION.md                       # Diese Datei
├── PrezioHub_Anleitung.md                 # PrezioHub Bedienungsanleitung
└── codemagic.yaml                         # CI/CD (Codemagic)
```

### Wichtige Konstanten (`lib/utils/constants.dart`)

```dart
appName = 'Prezio'
appVersion = '2.4.0'
defaultRecorderAddress = '192.168.4.1'
defaultRecorderPort = 8080
connectionTimeout = 10 Sekunden
requestTimeout = 30 Sekunden
defaultRecordingInterval = 10.0 Sekunden
```

### Riverpod-Provider (`lib/providers/app_providers.dart`)

| Provider | Typ | Beschreibung |
|---|---|---|
| `storageServiceProvider` | Provider | SharedPreferences |
| `measurementServiceProvider` | Provider | Messungsverwaltung |
| `pdfGeneratorProvider` | Provider | PDF-Erzeugung |
| `validationServiceProvider` | Provider | Druckpruefung |
| `weatherServiceProvider` | Provider | Wetterdaten |
| `nominatimServiceProvider` | Provider | Standortsuche |
| `supabaseUploadServiceProvider` | Provider | Supabase-Upload |
| `protocolStorageProvider` | Provider | Lokale Speicherung |
| `measurementsProvider` | StateNotifierProvider | Messungsliste (reaktiv) |
| `selectedMeasurementProvider` | StateProvider | Aktuell gewaehlte Messung |
| `protocolDataProvider` | StateProvider | Aktuelles Protokoll |

---

## 11. Ablauf (End-to-End)

### Vorbereitung (einmalig)

1. Prezio Recorder zusammenbauen + `setup_pi.sh` ausfuehren
2. Supabase-Projekt einrichten (Tabellen + Storage Bucket)
3. Supabase URL + Key in `lib/config/supabase_config.dart` eintragen
4. App auf Monteur-Handy installieren (IPA via Xcode / Codemagic)

### Messung durchfuehren

1. **Recorder einschalten** (Strom anschliessen)
   - Bootet automatisch (~30s)
   - WiFi AP "Prezio-Recorder" aktiv
   - Sensor wird erkannt
   - Secret Key wird generiert/geladen

2. **Handy verbinden**
   - WiFi "Prezio-Recorder" waehlen (Passwort: prezio2026)
   - Prezio-App oeffnen → Kolibri-Logo → "Verbinde..."
   - Automatische Authentifizierung via Key

3. **Aufzeichnung starten**
   - "Neue Aufzeichnung" → Name eingeben
   - PN und Medium waehlen (werden gesperrt!)
   - "Aufzeichnung starten" → laeuft im Hintergrund

4. **Warten** (Stunden/Tage)
   - Recorder zeichnet alle 10 Sekunden auf
   - Handy kann weg, Recorder laeuft autonom weiter
   - Maximal 10 Messungen werden gespeichert

5. **Messung auslesen**
   - Zurueck zum Recorder → Handy mit WiFi verbinden
   - "Aufzeichnung stoppen" → automatisch weiter
   - Oder: "Aufzeichnungen" → vergangene Messung waehlen

6. **Recorder WLAN aus + Internet**
   - App sendet WLAN-Aus-Befehl an Recorder (`POST /wifi/off`)
   - Recorder schaltet WLAN fuer 120 Sekunden ab, startet es dann automatisch wieder
   - Benutzer verbindet sich mit normalem WiFi / Mobilfunk
   - App prueft Internet automatisch alle 3 Sekunden
   - **Sofortiger CSV-Upload** zu Supabase (Rohdaten-Sicherung)
   - **Kein Power-Cycle noetig** - Recorder ist nach 2 Minuten wieder bereit

7. **Standort & Wetter**
   - GPS-Position wird abgerufen
   - Adresse wird automatisch ueber Nominatim aufgeloest
   - Standort kann manuell angepasst werden (Suchfeld mit Vorschlaegen)
   - Wetterdaten werden von Open-Meteo geladen

8. **Protokoll ausfuellen**
   - Projekt-Info eingeben
   - PN/Medium sind gesperrt (Anti-Manipulation)
   - **Druckkurve** wird direkt im Formular angezeigt
   - Validierung laeuft automatisch (inkl. Wetterdaten)
   - "Weiter zur Unterschrift"

9. **Unterschreiben**
   - Monteur unterschreibt auf dem Bildschirm (Normal oder Vollbild)
   - Druckkurve wird erfasst und auf Seite 2 des PDFs abgebildet
   - Zwei identische Unterschriftsfelder (links ausgefuellt, rechts leer fuer Projektleiter)
   - "Protokoll erstellen & speichern"

10. **Automatisch gespeichert**
    - Lokal auf dem Handy
    - PDF + CSV automatisch nach Supabase Storage hochgeladen
    - Metadaten in Supabase-Tabelle `protokolle`
    - SHA-256 Hash fuer Integritaet

---

## 12. Fehlerbehebung

### Recorder verbindet nicht

| Problem | Loesung |
|---|---|
| WiFi "Prezio-Recorder" nicht sichtbar (neuer Pi) | 3-5 Minuten warten (2-Phasen-Boot) |
| WiFi "Prezio-Recorder" nicht sichtbar (bestehender Pi) | Recorder Strom pruefen, 60s warten |
| WiFi sichtbar, aber keine Verbindung | Passwort: `prezio2026` |
| Verbunden, aber App zeigt "Verbinde..." | Per SSH pruefen: `sudo systemctl status prezio-recorder` |
| SSH: "HOST IDENTIFICATION HAS CHANGED" | `ssh-keygen -R 192.168.4.1` oder `ssh-keygen -R prezio-recorder.local` |
| SSH: "Permission denied" | User: `pi`, Passwort: `Prezio2000!` |

### PrezioHub / Firmware

| Problem | Loesung |
|---|---|
| "Kein Internet - Firmware-Cache nicht aktualisiert" | Hub einmal mit Internet starten |
| "Kein Internet und kein Firmware-Cache" | Hub muss zuerst einmal mit Internet gestartet werden |
| Dashboard zeigt "UPDATE FAELLIG" | In Pi-Steuerung → "Jetzt updaten" klicken |
| Imager: "Cache aelter als 24 Stunden" | Imager mit Internet starten |
| Imager: "Keine Firmware verfuegbar" | Hub oder Imager einmal mit Internet starten |

### Sensor

| Problem | Loesung |
|---|---|
| /health zeigt `sensorConnected: false` | USB-Kabel pruefen, Adapter-Treiber |
| Falsche Werte | Sensor-Adresse pruefen (Standard: 1) |
| Keine Seriennummer | Kabel/Adapter defekt |

### App

| Problem | Loesung |
|---|---|
| "Verbinde mit Prezio Recorder..." | Mit "Prezio-Recorder" WiFi verbinden |
| Supabase Upload fehlschlaegt | URL/Key in `supabase_config.dart` pruefen |
| "Cloud nicht konfiguriert" | Supabase URL + Key leer → eintragen |
| Wetterdaten nicht verfuegbar | Normal wenn auf Recorder-WiFi (kein Internet) |
| Standort nicht erkannt | GPS-Berechtigung in iOS-Einstellungen pruefen |

### Codemagic iOS-Build (ohne Xcode)

Die App wird ueber Codemagic.io gebaut (kein lokales Xcode noetig). Fuer unsigned IPA:

- **ios/Flutter/Release.xcconfig** enthaelt Code-Signing-Deaktivierung (CODE_SIGN_IDENTITY=, CODE_SIGNING_REQUIRED=NO)
- **codemagic.yaml** setzt zusaetzlich Umgebungsvariablen vor dem Build

Falls der Build mit "Development Team required" fehlschlaegt:
1. **Codemagic Dashboard** → App → Workflow → **Code signing** → Apple ID hinzufuegen (benoetigt Apple Developer Account, USD 99/Jahr)
2. Oder: Codemagic-Dokumentation zu "iOS code signing" pruefen – mit verbundenem Apple-Konto uebernimmt Codemagic die Signierung automatisch

Die unsigned IPA kann mit Sideloadly oder aehnlichen Tools auf Testgeraete installiert werden.

### Recorder-Logs einsehen

```bash
# Mit Recorder-WiFi verbinden, dann:
ssh pi@192.168.4.1

# Service-Logs live anzeigen
sudo journalctl -u prezio-recorder -f

# Service neustarten
sudo systemctl restart prezio-recorder

# Service-Status
sudo systemctl status prezio-recorder

# Key anzeigen
cat /home/pi/prezio_key.txt
```

---

## 13. Branding & Logos

| Verwendung | Logo | Datei |
|---|---|---|
| **App-Icon** (Launcher) | Kolibri (Hummingbird) | `assets/images/kolibri.png` |
| **App ConnectScreen** | Kolibri | `assets/images/kolibri.png` |
| **PDF-Protokoll Header** | Lehmann 2000 (offiziell) | `assets/images/lehmann2000.png` |
| **Settings (versteckt)** | Climartis (Hexagon, Mutterfirma) | `assets/images/climartis.png` |

- **Lehmann 2000** ist die Marke fuer Sanitaer-Druckpruefungen
- **Climartis** ist die Mutterfirma von Lehmann 2000 und Soleco
- Das Kolibri-Logo ersetzt den frueheren Kompass

### PDF-Struktur

| Seite | Inhalt |
|---|---|
| **Seite 1** | Header (Lehmann 2000), Ort/Datum (immer jetzt), Protokolltext, Druckinfo, Resultat, zwei identische Unterschriftsfelder (links Monteur ausgefuellt, rechts leer), Fusszeile |
| **Seite 2** | Nur Druckkurve (Diagramm), zentriert |

Datum im PDF ist immer `DateTime.now()` (aktueller Zeitpunkt bei Erstellung). Die Kurve wird per RepaintBoundary vom Chart-Widget erfasst; vor dem Erfassen scrollt die App nach oben und wartet auf das Rendering.

### Chart (Druckkurve)

- **fl_chart** mit Downsampling (~120 Punkte) und Moving Average (Fenster 7) fuer glatte Linien
- Keine Einzelpunkte, nur Linien
- Achsen mit festem Raster und lesbaren Labels

---

## 14. Cursor-Kontext (Prompt fuer neuen Chat)

Kopiere folgendes in einen neuen Cursor-Chat um den vollen Kontext zu haben:

---

**Prezio v2** ist eine Flutter-App (iOS/Android) fuer Druckpruefungen in der Sanitaerbranche (Firma: Soleco AG / Lehmann 2000, Zofingen).

**Pfad:** `C:\Users\noegl\OneDrive - Soleco AG\Desktop\Soleco Noé Desktop\tools\prezio_v2`
**Repo:** https://github.com/someFisherman/prezio-v2.git

**System:** Ein "Prezio Recorder" (Raspberry Pi 4B oder Zero 2 W) mit KELLER LEO5 Drucksensor, verbunden per USB-Seriell. Der Recorder erstellt ein WiFi Access Point ("Prezio-Recorder", 192.168.4.1). Ein headless Python-Script (`pi_recorder/pi_recorder.py`) steuert den Sensor und bietet eine HTTP REST API auf Port 8080. Die App authentifiziert sich ueber einen Secret Key (`/auth/key`), steuert Aufzeichnungen, laedt Messdaten als CSV, validiert automatisch (Gasgesetz fuer Luft, thermische Ausdehnung fuer Wasser, mit Wetterdaten-Korrektur via Open-Meteo), erkennt den Standort (GPS + Nominatim/OpenStreetMap), erstellt ein PDF-Protokoll mit Lehmann-2000-Logo und Unterschrift, und laedt alles automatisch nach Supabase (REST API, keine Kreditkarte, kein Login am Handy).

**Techstack:** Flutter 3.9+, Riverpod, fl_chart, pdf/printing, signature, http, geolocator, crypto. Pi: Python 3, pyserial, NetworkManager, systemd. Cloud: Supabase (REST API, kein SDK).

**Kein Login:** App-Zugang nur ueber Verbindung zum Prezio Recorder (Secret Key). Kein Passwort, kein Google/Microsoft-Login.

**Anti-Manipulation:** PN und Medium werden bei Aufzeichnungsstart festgelegt und im CSV-Header gespeichert. Bei der Auswertung sind diese Felder gesperrt. Validierung ist automatisch, der Monteur kann nicht manuell "gueltig/ungueltig" waehlen. CSV wird mit SHA-256 gehasht.

**Branding:** App-Logo = Kolibri, PDF-Logo = Lehmann 2000, Settings = Climartis (Mutterfirma).

**PDF:** Seite 1 = Protokoll + zwei identische Unterschriftsfelder (links Monteur, rechts leer). Seite 2 = nur Druckkurve. Datum immer aktuell. Chart: smooth mit Moving Average.

**Recorder:** `POST /wifi/off` schaltet WLAN 120s ab, dann automatisch wieder an – kein Power-Cycle noetig.

**Windows-Tools:** PrezioHub (zentrale Steuerung + Firmware-Updates), PrezioImager (SD-Karten flashen, vollautomatisch mit 2-Phasen-Boot), PrezioRecorder (Windows-Sensor-Recorder), PrezioDummy (Mock-Server). Alle als .exe via Installer verteilbar (`prezio_hub/build_all.py` + `prezio_hub/prezio_installer.iss`). Kein Python beim Endbenutzer noetig.

**Update-System:** Pi-Firmware (`pi_recorder.py`) wird direkt vom `main`-Branch auf GitHub gezogen (kein Release noetig). Hub cached die Dateien beim Start unter `%LOCALAPPDATA%\PrezioHub\firmware_cache\`. Updates werden per SFTP auf den Pi geschoben (kein Internet auf dem Pi noetig). Hub/Recorder/Dummy haben kein Auto-Update - neue .exe manuell verteilen.

**Wichtige Dateien:** Siehe `DOKUMENTATION.md` im Projektroot fuer die komplette Beschreibung aller Dateien, Services, Modelle, API-Endpunkte, Validierungslogik, Supabase-Setup und Hardware-Aufbau. Siehe `PrezioHub_Anleitung.md` fuer die Bedienung des PrezioHub Dashboards.

---

*Ende der Dokumentation*
