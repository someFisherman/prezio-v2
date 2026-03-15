# Prezio v2 - Vollstaendige Dokumentation

**Version:** 2.2.0  
**Stand:** Maerz 2026  
**Entwickelt fuer:** Soleco AG / Lehmann 2000, Zofingen  
**Plattformen:** iOS, Android (Flutter)  
**Repository:** https://github.com/someFisherman/prezio-v2.git

---

## Inhaltsverzeichnis

1. [Uebersicht](#1-uebersicht)
2. [Systemarchitektur](#2-systemarchitektur)
3. [Flutter-App (Smartphone)](#3-flutter-app-smartphone)
4. [Raspberry Pi Recorder](#4-raspberry-pi-recorder)
5. [Neues Geraet bauen (Pi Zero 2 W)](#5-neues-geraet-bauen-pi-zero-2-w)
6. [OneDrive-Anbindung](#6-onedrive-anbindung)
7. [Validierungslogik](#7-validierungslogik)
8. [Dateistruktur & Code-Referenz](#8-dateistruktur--code-referenz)
9. [Ablauf (End-to-End)](#9-ablauf-end-to-end)
10. [Fehlerbehebung](#10-fehlerbehebung)
11. [Cursor-Kontext (Prompt fuer neuen Chat)](#11-cursor-kontext-prompt-fuer-neuen-chat)

---

## 1. Uebersicht

Prezio ist eine Druckpruefungs-App fuer die Sanitaerbranche. Ein Monteur schliesst einen KELLER LEO5 Drucksensor an eine Leitung an, der Sensor ist per USB-Seriell mit einem Raspberry Pi verbunden. Die App auf dem Smartphone steuert die Aufzeichnung ueber WiFi, laedt die Messdaten, validiert automatisch ob die Leitung dicht ist, erstellt ein PDF-Protokoll mit Unterschrift und laedt alles automatisch nach OneDrive hoch.

### Kernprinzipien

- **Keine manuelle Manipulation**: PN (Betriebsdruck) und Medium (Luft/Wasser) werden bei Aufzeichnungsstart festgelegt und koennen nachtraeglich nicht geaendert werden
- **Automatische Validierung**: Das System entscheidet ob die Messung gueltig ist, nicht der Monteur
- **Automatische Ablage**: Protokolle werden ohne Benutzerinteraktion in OneDrive hochgeladen
- **Wetterdaten-Korrektur**: Aussentemperaturschwankungen werden bei der Toleranzberechnung beruecksichtigt

---

## 2. Systemarchitektur

```
┌──────────────────────┐     WiFi AP (192.168.4.1)     ┌──────────────────────┐
│                      │◄──────────────────────────────►│                      │
│   Raspberry Pi       │     HTTP REST API :8080        │   iPhone / Android   │
│   (Pi 4B / Zero 2 W) │                                │   Flutter App        │
│                      │                                │                      │
│   - WiFi Access Point│                                │   - Aufzeichnung     │
│   - KELLER LEO5      │                                │     starten/stoppen  │
│   - pi_recorder.py   │                                │   - CSV laden        │
│   - CSV-Speicherung  │                                │   - Validierung      │
│   - HTTP API         │                                │   - PDF erstellen    │
│                      │                                │   - OneDrive Upload  │
└────────┬─────────────┘                                └──────────────────────┘
         │ USB-Seriell                                           │
    ┌────┴─────┐                                          ┌──────┴───────┐
    │ KELLER   │                                          │  OneDrive    │
    │ LEO5     │                                          │  (Microsoft  │
    │ Sensor   │                                          │   Graph API) │
    └──────────┘                                          └──────────────┘
```

### Kommunikation

| Verbindung | Protokoll | Details |
|---|---|---|
| Pi ↔ Sensor | USB-Seriell (9600 Baud) | KELLER Protokoll (CRC16), Adresse 1 |
| Pi ↔ Smartphone | HTTP REST API | WiFi AP "Prezio-Recorder", IP 192.168.4.1:8080 |
| Smartphone ↔ OneDrive | HTTPS | Microsoft Graph API, OAuth2 PKCE |
| Smartphone ↔ Wetter-API | HTTPS | Open-Meteo (kostenlos, kein Key) |

---

## 3. Flutter-App (Smartphone)

### Technologie-Stack

- **Framework:** Flutter (Dart), SDK ^3.9.2
- **State Management:** Riverpod 2.6
- **Charts:** fl_chart
- **PDF:** pdf + printing
- **Signature:** signature 5.5
- **HTTP:** http (fuer Pi-API, OneDrive, Wetter)
- **OAuth:** flutter_web_auth_2 (Microsoft Login)
- **GPS:** geolocator (fuer Wetterdaten-Standort)
- **Crypto:** crypto (SHA-256 fuer CSV-Integritaet)

### Screen-Flow

```
HomeScreen
  ├── PiRecordingScreen       (Aufzeichnung starten/stoppen)
  ├── PiFileSelectionScreen   (Messung vom Pi waehlen → 1 antippen)
  │     └── ProtocolFormScreen  (Projekt-Info, Auto-Validierung, Wetter)
  │           └── SignatureScreen  (Unterschrift + Chart-Screenshot)
  │                 └── SendProtocolScreen  (Speichern + OneDrive-Upload)
  ├── MeasurementListScreen   (Alle geladenen Messungen)
  │     └── MeasurementDetailScreen  (Details + Chart)
  └── SettingsScreen          (Monteur, Pi-IP, OneDrive-Login)
```

### Wichtige Services

| Service | Datei | Aufgabe |
|---|---|---|
| PiConnectionService | `pi_connection_service.dart` | HTTP-Client fuer Pi-API |
| MeasurementService | `measurement_service.dart` | Messungen laden, verwalten, exportieren |
| CsvParserService | `csv_parser_service.dart` | CSV parsen (inkl. Metadaten-Header) |
| ValidationService | `validation_service.dart` | Druckpruefung validieren |
| WeatherService | `weather_service.dart` | Wetterdaten von Open-Meteo holen |
| OneDriveService | `onedrive_service.dart` | OAuth2 + Microsoft Graph Upload |
| PdfGeneratorService | `pdf_generator_service.dart` | A4-PDF "Lehmann 2000" generieren |
| ProtocolStorageService | `protocol_storage_service.dart` | Lokale Ordnerstruktur + Metadaten |
| StorageService | `storage_service.dart` | SharedPreferences (Einstellungen) |

### Datenmodelle

| Modell | Datei | Felder |
|---|---|---|
| Sample | `sample.dart` | index, timestamp, timestampUtc, pressureBar, temperatureC, pressureRounded, temperatureRounded |
| Measurement | `measurement.dart` | id, filename, startTime, endTime, duration, samples[], validationStatus, metadata |
| CsvMetadata | `measurement.dart` | name, pn, medium, intervalS |
| ProtocolData | `protocol_data.dart` | measurement, objectName, projectName, author, nominalPressure, testMedium, testPressure, result, passed, technicianName, signature, chartImage, notes |
| TestMedium | `protocol_data.dart` | air (Faktor 1.1), water (Faktor 1.5) |

### CSV-Format (vom Pi)

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

## 4. Raspberry Pi Recorder

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

### Pi Recorder Script (`pi_recorder.py`)

Headless Python-Script das:
1. Den KELLER LEO5 Sensor per USB-Seriell (9600 Baud) anspricht
2. Messwerte (Druck P1, Temperatur TOB1) in 10-Sekunden-Zyklen aufzeichnet
3. CSV-Dateien mit Metadaten-Headern in `./data/` speichert
4. Eine HTTP REST API auf Port 8080 bereitstellt

### API-Endpunkte

| Methode | Pfad | Beschreibung |
|---|---|---|
| `GET` | `/health` | Sensor-Status, Seriennummer, Verbindung |
| `GET` | `/files` | Liste aller CSV-Dateien (Name, Groesse, Datum) |
| `GET` | `/files/{name}` | CSV-Datei herunterladen |
| `DELETE` | `/files/{name}` | CSV-Datei loeschen |
| `POST` | `/recording/start` | Aufzeichnung starten (JSON: name, pn, medium, interval_s) |
| `POST` | `/recording/stop` | Aufzeichnung stoppen |
| `GET` | `/recording/status` | Status (laeuft?, Name, Dauer, Samples, letzte Werte) |

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

### Schritt-fuer-Schritt Aufbau

#### 1. SD-Karte vorbereiten

1. **Raspberry Pi Imager** herunterladen: https://www.raspberrypi.com/software/
2. Imager starten:
   - **Geraet:** Raspberry Pi Zero 2 W
   - **OS:** "Raspberry Pi OS Lite (64-bit)" (unter "Raspberry Pi OS (other)")
   - **Speicher:** 32 GB microSD
3. **Vor dem Schreiben** → Zahnrad-Icon / "Einstellungen bearbeiten":
   - Hostname: `prezio-pi`
   - SSH aktivieren: Ja, mit Passwort
   - Benutzername: `pi`
   - Passwort: `Prezio2026!` (oder ein eigenes)
   - **WLAN konfigurieren:** Dein Buero-/Heim-WiFi eintragen (fuer Ersteinrichtung!)
   - Zeitzone: `Europe/Zurich`
4. "Schreiben" klicken und warten

#### 2. Pi zusammenbauen

1. microSD in den Pi Zero 2 W einsetzen
2. USB-OTG-Adapter an den **Daten-Micro-USB** (nicht Power!) anschliessen
3. USB-Seriell-Adapter mit KELLER LEO5 verbinden
4. USB-Seriell-Adapter an den OTG-Adapter stecken
5. Micro-USB-Netzteil an den **Power-Port** anschliessen

**WICHTIG beim Pi Zero 2 W:** Es gibt zwei Micro-USB-Ports!
- Links (aussen): **Power** (nur Strom)
- Rechts (innen, neben HDMI): **Daten** (hier den OTG-Adapter anschliessen)

#### 3. Ersteinrichtung per SSH

1. Pi bootet (~60 Sekunden warten)
2. Auf dem PC (PowerShell):

```bash
ssh pi@prezio-pi.local
```

Falls `prezio-pi.local` nicht gefunden wird: IP im Router nachschauen.

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

#### 4. Testen

1. Auf dem Handy: WiFi "Prezio-Recorder" suchen und verbinden (Passwort: `prezio2026`)
2. Im Browser oeffnen: `http://192.168.4.1:8080/health`
3. Sollte JSON mit Sensor-Status zeigen
4. In der Prezio-App: "Aufzeichnung starten / stoppen" → Sensor-Status pruefen

#### 5. Fertig!

Ab jetzt: Pi mit Strom versorgen → bootet automatisch → WiFi AP startet → Sensor wird erkannt → App verbinden und arbeiten.

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
| Setup-Skript | Identisch | Identisch |

Das Setup-Skript (`setup_pi.sh`) funktioniert identisch auf beiden Modellen.

### Mehrere Geraete

Jedes Geraet ist unabhaengig. Bei mehreren Geraeten:
- Jeder Pi hat die gleiche SSID ("Prezio-Recorder") und IP (192.168.4.1)
- Das Handy verbindet sich immer nur mit dem Pi der gerade in Reichweite ist
- Kein Konflikt, da nie zwei Pis gleichzeitig in Reichweite sein sollten
- Falls doch: SSID anpassen mit `sudo bash setup_pi.sh "Prezio-Geraet-2"`

---

## 6. OneDrive-Anbindung

### Funktionsweise

Die App nutzt die **Microsoft Graph API** um Protokolle direkt in OneDrive hochzuladen. Der Upload geschieht vollautomatisch nach dem Speichern - der Monteur bekommt davon nichts mit.

### Zielordner

```
OneDrive
└── Prezio
    └── Protokolle
        ├── Heizung_OG_2026-03-15/
        │   ├── Druckprotokoll_15-03-2026_OK.pdf
        │   ├── Messdaten.csv
        │   └── metadata.json
        └── Badezimmer_EG_2026-03-16/
            ├── Druckprotokoll_16-03-2026_Nicht_OK.pdf
            ├── Messdaten.csv
            └── metadata.json
```

### Azure AD Einrichtung (einmalig)

1. **portal.azure.com** oeffnen, mit Soleco-Konto anmelden
2. "App-Registrierungen" suchen → "Neue Registrierung"
3. Einstellungen:
   - Name: `Prezio`
   - Kontotypen: "Nur Konten in diesem Organisationsverzeichnis"
   - Umleitungs-URI: Plattform **"Oeffentlicher Client/nativ"** → URI: `prezio://auth`
4. **Anwendungs-ID (Client-ID)** kopieren
5. Unter "API-Berechtigungen":
   - "Berechtigung hinzufuegen" → Microsoft Graph → Delegiert → `Files.ReadWrite`
   - "Administratorzustimmung erteilen" klicken
6. Client-ID in `lib/utils/constants.dart` eintragen:

```dart
static const String azureClientId = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx';
```

### Geraet einrichten (einmalig pro Handy)

1. App oeffnen → Einstellungen → "Mit Microsoft anmelden"
2. Microsoft-Login im Browser erscheint → Mit Soleco-Konto anmelden
3. Fertig! Token wird gespeichert, ab jetzt automatisch

**Szenario A (empfohlen):** Admin loggt sich auf jedem Monteur-Handy mit dem gleichen Soleco-Konto ein. Alle Protokolle landen zentral in einem OneDrive.

### Technische Details

- **OAuth2 mit PKCE** (kein Client Secret noetig fuer Mobile Apps)
- **Refresh Token** wird in SharedPreferences gespeichert
- **Automatische Token-Erneuerung** bei jedem Upload
- **Fallback**: Wenn Upload fehlschlaegt → lokal gespeichert, kein Datenverlust
- **Upload-Limit**: Einzeldateien < 4 MB (fuer groessere: Resumable Upload noetig, aktuell nicht implementiert - reicht aber fuer PDFs und CSVs)

---

## 7. Validierungslogik

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

### Pruefergebnis

```
Fehler = |Enddruck - erwarteteDruck|

Wenn Fehler ≤ Toleranz → BESTANDEN (kein Leck)
Wenn Fehler > Toleranz  → NICHT BESTANDEN (moegliche Leckage)
```

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

## 8. Dateistruktur & Code-Referenz

```
prezio_v2/
├── lib/
│   ├── main.dart                          # App-Einstiegspunkt
│   ├── app.dart                           # MaterialApp + Theme
│   │
│   ├── models/
│   │   ├── models.dart                    # Barrel-Export
│   │   ├── measurement.dart               # Measurement, CsvMetadata, ValidationStatus
│   │   ├── sample.dart                    # Sample (Einzelmesswert)
│   │   └── protocol_data.dart             # ProtocolData, TestMedium
│   │
│   ├── screens/
│   │   ├── screens.dart                   # Barrel-Export
│   │   ├── home_screen.dart               # Dashboard
│   │   ├── pi_recording_screen.dart       # Pi-Aufzeichnung steuern
│   │   ├── pi_file_selection_screen.dart   # Messung vom Pi waehlen (Einzelauswahl)
│   │   ├── protocol_form_screen.dart       # Protokoll-Formular + Validierung + Wetter
│   │   ├── signature_screen.dart           # Unterschrift erfassen
│   │   ├── send_protocol_screen.dart       # Speichern + OneDrive-Upload
│   │   ├── measurement_list_screen.dart    # Messungsliste (Tabs)
│   │   ├── measurement_detail_screen.dart  # Messungsdetails + Chart
│   │   └── settings_screen.dart            # Einstellungen + OneDrive-Login
│   │
│   ├── services/
│   │   ├── services.dart                  # Barrel-Export
│   │   ├── pi_connection_service.dart      # HTTP-Client fuer Pi
│   │   ├── measurement_service.dart        # Messungsverwaltung
│   │   ├── csv_parser_service.dart         # CSV parsen/generieren
│   │   ├── validation_service.dart         # Druckpruefung validieren
│   │   ├── weather_service.dart            # Open-Meteo Wetter-API
│   │   ├── onedrive_service.dart           # Microsoft Graph OneDrive
│   │   ├── pdf_generator_service.dart      # PDF "Lehmann 2000"
│   │   ├── protocol_storage_service.dart   # Lokale Speicherung
│   │   ├── storage_service.dart            # SharedPreferences
│   │   └── email_service.dart              # E-Mail (Legacy, nicht aktiv)
│   │
│   ├── providers/
│   │   ├── providers.dart                 # Barrel-Export
│   │   └── app_providers.dart              # Riverpod-Provider
│   │
│   ├── widgets/
│   │   ├── widgets.dart                   # Barrel-Export
│   │   ├── pressure_chart.dart             # Druck/Temperatur-Chart (fl_chart)
│   │   └── measurement_card.dart           # Messungs-Karte
│   │
│   └── utils/
│       ├── utils.dart                     # Barrel-Export
│       ├── constants.dart                  # App-Konstanten, Azure-ID, Storage-Keys
│       ├── formatters.dart                 # Zahlen/Datum-Formatierung (de_CH)
│       └── theme.dart                      # Material Theme
│
├── pi_recorder/
│   ├── pi_recorder.py                     # Headless Python-Recorder + HTTP API
│   ├── setup_pi.sh                        # Pi-Setup (WiFi AP, Service, Python)
│   ├── requirements.txt                   # pyserial>=3.5
│   ├── howto.txt                          # Aufbau-Anleitung (Kurzform)
│   └── data/                              # CSV-Dateien (zur Laufzeit erstellt)
│
├── pc_recorder/                           # PC-Version des Recorders (mit GUI)
├── dummy_server/                          # Test-Server fuer Entwicklung
├── assets/images/                         # App-Assets
├── ios/                                   # iOS-spezifisch
├── android/                               # Android-spezifisch
├── pubspec.yaml                           # Flutter-Abhaengigkeiten
└── codemagic.yaml                         # CI/CD (Codemagic)
```

### Wichtige Konstanten (`lib/utils/constants.dart`)

```dart
appName = 'Prezio'
appVersion = '2.2.0'
defaultPiAddress = '192.168.4.1'
defaultPiPort = 8080
connectionTimeout = 10 Sekunden
requestTimeout = 30 Sekunden
defaultRecordingInterval = 10.0 Sekunden
azureClientId = ''  // Nach Azure-Registrierung eintragen
```

### Riverpod-Provider (`lib/providers/app_providers.dart`)

| Provider | Typ | Beschreibung |
|---|---|---|
| `storageServiceProvider` | Provider | SharedPreferences |
| `measurementServiceProvider` | Provider | Messungsverwaltung |
| `pdfGeneratorProvider` | Provider | PDF-Erzeugung |
| `validationServiceProvider` | Provider | Druckpruefung |
| `weatherServiceProvider` | Provider | Wetterdaten |
| `oneDriveServiceProvider` | Provider | OneDrive-Upload |
| `protocolStorageProvider` | Provider | Lokale Speicherung |
| `measurementsProvider` | StateNotifierProvider | Messungsliste (reaktiv) |
| `selectedMeasurementProvider` | StateProvider | Aktuell gewaehlte Messung |
| `protocolDataProvider` | StateProvider | Aktuelles Protokoll |

---

## 9. Ablauf (End-to-End)

### Vorbereitung (einmalig)

1. Pi zusammenbauen + setup_pi.sh ausfuehren
2. Azure AD App registrieren, Client-ID eintragen
3. App auf Monteur-Handy installieren
4. In Einstellungen: Monteur-Name eintragen, "Mit Microsoft anmelden"

### Messung durchfuehren

1. **Pi einschalten** (Strom anschliessen)
   - Bootet automatisch (~30s)
   - WiFi AP "Prezio-Recorder" aktiv
   - Sensor wird erkannt

2. **Handy verbinden**
   - WiFi "Prezio-Recorder" waehlen (Passwort: prezio2026)
   - Prezio-App oeffnen

3. **Aufzeichnung starten**
   - "Aufzeichnung starten / stoppen" antippen
   - Name eingeben (z.B. "Heizung OG Muster")
   - PN und Medium waehlen (werden gesperrt!)
   - "Aufzeichnung starten" → laeuft im Hintergrund

4. **Warten** (Stunden/Tage)
   - Pi zeichnet alle 10 Sekunden auf
   - Handy kann weg, Pi laeuft autonom weiter

5. **Messung auslesen**
   - Zurueck zum Pi → Handy mit WiFi verbinden
   - "Messungen vom Pi laden" → Messung antippen

6. **Protokoll erstellen**
   - Projekt-Info ausfuellen
   - PN/Medium sind gesperrt (Anti-Manipulation)
   - Validierung laeuft automatisch (inkl. Wetterdaten falls Internet)
   - "Weiter zur Unterschrift"

7. **Unterschreiben**
   - Monteur unterschreibt auf dem Bildschirm
   - "Protokoll erstellen & speichern"

8. **Automatisch gespeichert**
   - Lokal auf dem Handy
   - Automatisch nach OneDrive hochgeladen
   - PDF + CSV + Metadaten (mit SHA-256 Hash)

---

## 10. Fehlerbehebung

### Pi verbindet nicht

| Problem | Loesung |
|---|---|
| WiFi "Prezio-Recorder" nicht sichtbar | Pi Strom pruefen, 60s warten |
| WiFi sichtbar, aber keine Verbindung | Passwort: `prezio2026` |
| Verbunden, aber kein Zugriff auf 192.168.4.1 | `setup_pi.sh` nochmal ausfuehren |
| SSH: "HOST IDENTIFICATION HAS CHANGED" | `ssh-keygen -R prezio-pi.local` |

### Sensor

| Problem | Loesung |
|---|---|
| /health zeigt `sensorConnected: false` | USB-Kabel pruefen, Adapter-Treiber |
| Falsche Werte | Sensor-Adresse pruefen (Standard: 1) |
| Keine Seriennummer | Kabel/Adapter defekt |

### App

| Problem | Loesung |
|---|---|
| "Keine Verbindung zum Pi" | Mit "Prezio-Recorder" WiFi verbinden |
| OneDrive Upload fehlschlaegt | In Einstellungen neu anmelden |
| Wetterdaten nicht verfuegbar | Normal wenn auf Pi-WiFi (kein Internet), Standard-Toleranz wird genutzt |

### Pi-Logs einsehen

```bash
# Mit Pi-WiFi verbinden, dann:
ssh pi@192.168.4.1

# Service-Logs live anzeigen
sudo journalctl -u prezio-recorder -f

# Service neustarten
sudo systemctl restart prezio-recorder

# Service-Status
sudo systemctl status prezio-recorder
```

---

## 11. Cursor-Kontext (Prompt fuer neuen Chat)

Kopiere folgendes in einen neuen Cursor-Chat um den vollen Kontext zu haben:

---

**Prezio v2** ist eine Flutter-App (iOS/Android) fuer Druckpruefungen in der Sanitaerbranche (Firma: Soleco AG / Lehmann 2000, Zofingen).

**Pfad:** `C:\Users\noegl\OneDrive - Soleco AG\Desktop\Soleco Noé Desktop\tools\prezio_v2`
**Repo:** https://github.com/someFisherman/prezio-v2.git

**System:** Ein Raspberry Pi (4B oder Zero 2 W) mit KELLER LEO5 Drucksensor, verbunden per USB-Seriell. Der Pi erstellt ein WiFi Access Point ("Prezio-Recorder", 192.168.4.1). Ein headless Python-Script (`pi_recorder/pi_recorder.py`) steuert den Sensor und bietet eine HTTP REST API auf Port 8080. Die Flutter-App verbindet sich per WiFi, startet/stoppt Aufzeichnungen, laedt Messdaten als CSV, validiert automatisch (Gasgesetz fuer Luft, thermische Ausdehnung fuer Wasser, mit Wetterdaten-Korrektur via Open-Meteo), erstellt ein PDF-Protokoll mit Unterschrift und laedt alles automatisch nach OneDrive (Microsoft Graph API, OAuth2 PKCE).

**Techstack:** Flutter 3.9+, Riverpod, fl_chart, pdf/printing, signature, http, geolocator, flutter_web_auth_2, crypto. Pi: Python 3, pyserial, NetworkManager, systemd.

**Anti-Manipulation:** PN und Medium werden bei Aufzeichnungsstart festgelegt und im CSV-Header gespeichert. Bei der Auswertung sind diese Felder gesperrt. Validierung ist automatisch, der Monteur kann nicht manuell "gueltig/ungueltig" waehlen. CSV wird mit SHA-256 gehasht.

**Wichtige Dateien:** Siehe `DOKUMENTATION.md` im Projektroot fuer die komplette Beschreibung aller Dateien, Services, Modelle, API-Endpunkte, Validierungslogik und Hardware-Setup.

---

*Ende der Dokumentation*
