# Prezio v2 - Druckpruefungssystem

**Soleco AG / Lehmann 2000, Zofingen**  
**Stand:** Maerz 2026

Cross-Platform Druckpruefungssystem fuer die Sanitaerbranche. Bestehend aus einer Smartphone-App (iOS & Android), einem Raspberry Pi Recorder, Cloud-Speicher (Supabase) und Windows-Werkzeugen (PrezioHub).

---

## Systemuebersicht

```
┌──────────────────────┐     WiFi AP (192.168.4.1)     ┌──────────────────────┐
│   Prezio Recorder    │◄──────────────────────────────►│   iPhone / Android   │
│   (Raspberry Pi)     │     HTTP REST API :8080        │   Flutter App        │
│                      │                                │                      │
│   - KELLER LEO5      │                                │   - Aufzeichnung     │
│   - CSV-Speicherung  │                                │   - Auto-Validierung │
│   - WiFi AP          │                                │   - PDF-Protokoll    │
│   - Secret Key Auth  │                                │   - Supabase Upload  │
└──────────┬───────────┘                                └──────────┬───────────┘
           │ USB-Seriell                                           │ HTTPS
      ┌────┴─────┐                                        ┌───────┴────────┐
      │ KELLER   │                                        │ Supabase       │
      │ LEO5     │                                        │ (DB + Storage) │
      └──────────┘                                        └────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                        PrezioHub (Windows-PC)                                │
│                                                                              │
│   - Zentrale Steuerung aller Werkzeuge                                       │
│   - Pi-Fernsteuerung (SSH, Reboot, Logs)                                     │
│   - Firmware-Update fuer den Pi (kein Internet auf Pi noetig)                │
│   - SD-Karten flashen mit PrezioImager (vollautomatisch)                     │
│   - Supabase Storage durchsuchen und herunterladen                           │
│   - Firmware-Cache: Laedt pi_recorder.py etc. von GitHub beim Start          │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Komponenten

### Smartphone-App (Flutter)

Die Haupt-App fuer Monteure. Verbindet sich per WiFi mit dem Prezio Recorder, steuert Aufzeichnungen, validiert Druckpruefungen automatisch (inkl. Wetterdaten-Korrektur), erstellt PDF-Protokolle mit Unterschrift und laedt alles nach Supabase hoch.

- **Plattformen:** iOS, Android
- **Framework:** Flutter (Dart), Riverpod
- **Pfad:** `lib/`

### Prezio Recorder (Raspberry Pi)

Headless Python-Script auf dem Pi. Liest den KELLER LEO5 Drucksensor per USB-Seriell aus, speichert CSV-Dateien und stellt eine HTTP REST API bereit.

- **Hardware:** Pi 4B oder Pi Zero 2 W
- **Software:** `pi_recorder/pi_recorder.py`
- **WiFi AP:** `Prezio-Recorder` (Passwort: `prezio2026`, IP: `192.168.4.1`)
- **SSH:** User `pi`, Passwort `Prezio2000!`

### PrezioHub (Windows)

Zentrale Steuerungsoberflaeche fuer Techniker und Entwickler. Buendelt alle Werkzeuge, Pi-Fernsteuerung, Firmware-Updates, Supabase-Zugriff und Dokumentationen.

- **Framework:** Python / Tkinter
- **Pfad:** `prezio_hub/`
- **Firmware-Cache:** Laedt `pi_recorder.py`, `setup_pi.sh`, `requirements.txt`, `howto.txt` beim Start von GitHub und speichert sie unter `%LOCALAPPDATA%\PrezioHub\firmware_cache\`

### PrezioImager (Windows)

SD-Karten Flash Tool. Laedt Raspberry Pi OS herunter, flasht es auf SD-Karten und richtet den Prezio Recorder vollautomatisch ein (WiFi AP, SSH, Service). Der Pi ist nach dem Flashen und ca. 3-5 Minuten Bootzeit sofort einsatzbereit - keine manuelle Einrichtung noetig.

- **Framework:** Python / Tkinter / Win32 API
- **Pfad:** `pi_recorder/prezio_imager.py`
- **2-Phasen-Boot:** Phase 1 (erster Boot) kopiert Dateien und erstellt einen Setup-Service, dann Reboot. Phase 2 (zweiter Boot) konfiguriert WiFi AP und installiert den Recorder-Service.

### PC Recorder (Windows)

Windows-Version des Sensor-Recorders mit grafischer Oberflaeche. Liest den KELLER LEO5 per COM-Port aus und stellt einen HTTP-Server bereit.

- **Framework:** Python / Tkinter
- **Pfad:** `pc_recorder/`

### Dummy Server

Mock-Server der den Raspberry Pi simuliert. Fuer Entwicklung und Tests ohne echten Sensor.

- **Pfad:** `dummy_server/`

### Supabase (Cloud)

Kostenloser Cloud-Speicher fuer Protokolle und Rohdaten. Kein Login am Handy noetig, kein SDK - reine REST API.

- **Dashboard:** https://supabase.com/dashboard/project/ndqisdqdhzeenvjkkuxd

---

## Installation (Windows-Werkzeuge)

### Installer (empfohlen)

`PrezioHub_Setup.exe` installiert alle Windows-Werkzeuge:

- PrezioHub, PrezioImager, PrezioRecorder, PrezioDummy
- Startmenue-Eintraege und optionale Desktop-Verknuepfungen
- Kein Python noetig - alles ist als eigenstaendige .exe gebuendelt

### Aus dem Quellcode

```bash
cd prezio_v2/prezio_hub
python prezio_hub.py

# Alle .exe bauen
python build_all.py

# Installer erstellen (Inno Setup noetig)
# prezio_installer.iss in Inno Setup oeffnen und kompilieren
```

---

## Update-Workflow

### Pi-Firmware updaten (pi_recorder.py)

Wenn eine neue Version von `pi_recorder.py` (oder `setup_pi.sh`, `requirements.txt`) entwickelt wird:

1. Aenderungen in `pi_recorder.py` vornehmen
2. `VERSION` Konstante erhoehen (z.B. `VERSION = "1.2.0"`)
3. `git add . && git commit -m "Pi Recorder v1.2.0" && git push`
4. **Fertig!** Kein GitHub Release noetig.

PrezioHub und PrezioImager ziehen die Dateien automatisch vom `main`-Branch auf GitHub.

**Update auf bestehenden Pi aufspielen:**
1. PrezioHub mit Internet starten (Cache wird aktualisiert)
2. Mit Pi-WiFi verbinden
3. Dashboard zeigt oranges Banner "UPDATE FAELLIG"
4. In Pi-Steuerung: "Jetzt updaten" klicken
5. Datei wird per SFTP hochgeladen, Service wird neugestartet

**Neue SD-Karte flashen:**
- PrezioImager verwendet automatisch die gecachte Firmware

### Hub / Recorder / Dummy updaten

Diese Programme haben kein Auto-Update. Neues `.exe` bauen und manuell verteilen:

1. Code aendern, `VERSION` erhoehen
2. `python build_all.py`
3. Inno Setup kompilieren
4. Installer verteilen

---

## Smartphone-App

### Features

- CSV-Dateien vom Raspberry Pi laden (via WiFi)
- Aufzeichnungen starten und stoppen
- Messungen automatisch validieren (Gasgesetz, thermische Ausdehnung, Wetterdaten)
- Druckverlauf als Kurve visualisieren
- PDF-Protokoll mit Unterschrift generieren
- Automatischer Upload nach Supabase

### Build

```bash
flutter pub get
flutter run

# Android APK
flutter build apk --release

# iOS (ueber Codemagic oder lokal mit Xcode)
flutter build ios --release
```

---

## Dokumentation

| Dokument | Beschreibung |
|----------|-------------|
| [Technische Dokumentation](DOKUMENTATION.md) | Vollstaendige Referenz aller Komponenten |
| [PrezioHub Anleitung](PrezioHub_Anleitung.md) | Bedienung des PrezioHub Dashboards |
| [Pi Image klonen](ANLEITUNG_PI_KLONEN.md) | SD-Karte flashen (PrezioImager) und manuelles Klonen |
| [App Store & Google Play](ANLEITUNG_APPSTORE_CONNECT_CODEMAGIC.md) | iOS/Android Signierung und Deployment |
| [Pi Recorder Setup](pi_recorder/howto.txt) | Manuelle Ersteinrichtung eines Raspberry Pi |
| [PC Recorder](pc_recorder/README.md) | Windows-Sensor-Tool Handbuch |
| [Dummy Server](dummy_server/README.md) | Mock-Server fuer Entwicklung |

---

## Projektstruktur

```
prezio_v2/
├── lib/                    # Flutter-App (Smartphone)
│   ├── models/             # Datenmodelle
│   ├── screens/            # UI Screens
│   ├── services/           # Business Logic
│   ├── providers/          # Riverpod State Management
│   ├── widgets/            # Wiederverwendbare Widgets
│   └── utils/              # Hilfsfunktionen
├── pi_recorder/            # Raspberry Pi Recorder + Imager
│   ├── pi_recorder.py      # Recorder-Script (auf dem Pi)
│   ├── prezio_imager.py    # SD-Karten Flash Tool (Windows)
│   ├── setup_pi.sh         # Pi-Setup (WiFi AP, Service)
│   ├── requirements.txt    # Python-Abhaengigkeiten
│   └── howto.txt           # Manuelle Setup-Anleitung
├── pc_recorder/            # Windows PC Recorder
├── dummy_server/           # Mock-Server
├── prezio_hub/             # PrezioHub Dashboard + Build-Scripts
│   ├── prezio_hub.py       # Hauptanwendung
│   ├── build_all.py        # Baut alle .exe
│   ├── prezio_installer.iss # Inno Setup Script
│   └── dist/PrezioHub/     # Fertige Distribution (nach Build)
├── assets/images/          # App-Logos (Kolibri, Lehmann 2000, Climartis)
├── ios/                    # iOS-spezifisch
├── android/                # Android-spezifisch
├── DOKUMENTATION.md        # Vollstaendige technische Dokumentation
├── PrezioHub_Anleitung.md  # PrezioHub Bedienungsanleitung
└── pubspec.yaml            # Flutter-Abhaengigkeiten
```

---

## Lizenz

Proprietaer - Soleco AG
