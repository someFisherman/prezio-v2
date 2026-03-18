# Prezio v2 - Druckpruefungssystem

**Soleco AG / Lehmann 2000, Zofingen**  
**Stand:** Maerz 2026

Cross-Platform Druckpruefungssystem fuer die Sanitaerbranche. Bestehend aus einer Smartphone-App (iOS & Android), einem Raspberry Pi Recorder, Cloud-Speicher (Supabase) und Windows-Werkzeugen.

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
- **Pfad:** `pi_recorder/`

### PrezioHub (Windows)

Zentrale Steuerungsoberflaeche fuer Techniker und Entwickler. Buendelt alle Werkzeuge, Pi-Fernsteuerung, Supabase-Zugriff und Dokumentationen.

- **Framework:** Python / Tkinter
- **Pfad:** `prezio_hub/`

### PrezioImager (Windows)

SD-Karten Flash Tool. Laedt das Raspberry Pi OS herunter und flasht es auf SD-Karten fuer neue Prezio Recorder. Benoetigt Admin-Rechte.

- **Framework:** Python / Tkinter / Win32 API
- **Pfad:** `pi_recorder/prezio_imager.py`

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

`PrezioHub_Setup_1.0.0.exe` installiert alle Windows-Werkzeuge:

- PrezioHub, PrezioImager, PrezioRecorder, PrezioDummy
- Startmenue-Eintraege und optionale Desktop-Verknuepfungen
- Kein Python noetig - alles ist als eigenstaendige .exe gebuendelt

### Aus dem Quellcode

```bash
# Einzelnes Tool starten
cd prezio_v2/prezio_hub
python prezio_hub.py

# Alle .exe bauen
python build_all.py

# Installer erstellen (Inno Setup noetig)
# prezio_installer.iss in Inno Setup oeffnen und kompilieren
```

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
| [App Store & Google Play](ANLEITUNG_APPSTORE_CONNECT_CODEMAGIC.md) | iOS/Android Signierung und Deployment |
| [Pi Image klonen](ANLEITUNG_PI_KLONEN.md) | SD-Karte sichern und auf neue Pis flashen |
| [PrezioHub Anleitung](PrezioHub_Anleitung.md) | Bedienung des PrezioHub Dashboards |
| [Pi Recorder Setup](pi_recorder/howto.txt) | Ersteinrichtung eines neuen Raspberry Pi |
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
├── pc_recorder/            # Windows PC Recorder
├── dummy_server/           # Mock-Server
├── prezio_hub/             # PrezioHub Dashboard + Build-Scripts
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
