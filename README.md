# Prezio V2 - Druckprotokoll App

Cross-Platform App (iOS & Android) zur Verarbeitung von Druckmessungen.

## Features

- CSV-Dateien vom Raspberry Pi laden (via WiFi oder Dateiauswahl)
- Messungen in Liste anzeigen
- Messungen validieren (gültig/ungültig markieren)
- Druckverlauf als Kurve visualisieren
- Druckprotokoll automatisch generieren (PDF)
- Unterschrift erfassen (Vollbild-Signaturfeld)
- Protokoll per E-Mail versenden

## Architektur

```
lib/
├── main.dart              # App-Einstiegspunkt
├── app.dart               # MaterialApp-Konfiguration
├── models/                # Datenmodelle
│   ├── sample.dart        # Einzelner Messpunkt
│   ├── measurement.dart   # Komplette Messung
│   └── protocol_data.dart # Protokoll-Daten
├── services/              # Business Logic
│   ├── csv_parser_service.dart
│   ├── pi_connection_service.dart
│   ├── measurement_service.dart
│   ├── pdf_generator_service.dart
│   ├── email_service.dart
│   └── storage_service.dart
├── providers/             # Riverpod State Management
├── screens/               # UI Screens
│   ├── home_screen.dart
│   ├── measurement_list_screen.dart
│   ├── measurement_detail_screen.dart
│   ├── protocol_form_screen.dart
│   ├── signature_screen.dart
│   ├── send_protocol_screen.dart
│   └── settings_screen.dart
├── widgets/               # Wiederverwendbare Widgets
│   ├── measurement_card.dart
│   └── pressure_chart.dart
└── utils/                 # Hilfsfunktionen
    ├── formatters.dart    # Rundung, Datumsformatierung
    ├── constants.dart
    └── theme.dart
```

## CSV-Format

Die App erwartet CSV-Dateien im folgenden Format:

```csv
No,Datetime [local time],Datetime [UTC],P1 [bar],TOB1 [°C],P1 rounded [bar],TOB1 rounded [°C]
1,13.03.2026 15:37:23,2026-03-13T14:37:23.454963Z,-0.001094818,25.71664429,-0.00,25.72
2,13.03.2026 15:37:24,2026-03-13T14:37:24.456390Z,-0.001752853,25.71664429,-0.00,25.72
...
```

## Raspberry Pi Verbindung

Die App kommuniziert mit dem Raspberry Pi über WiFi:

1. Der Pi erstellt ein eigenes WLAN-Netzwerk (Access Point)
2. Das Handy verbindet sich mit diesem WLAN
3. Die App lädt Dateien über HTTP vom Pi (Standard: `http://192.168.4.1:8080`)

### Pi-Server Endpunkte

Der HTTP-Server auf dem Pi muss folgende Endpunkte bereitstellen:

- `GET /health` - Health-Check
- `GET /files` - Liste aller CSV-Dateien (JSON-Array)
- `GET /files/{filename}` - Download einer spezifischen Datei

## Entwicklung

### Voraussetzungen

- Flutter SDK 3.x
- Dart 3.x
- Android Studio / Xcode (für Emulator/Simulator)

### Setup

```bash
cd prezio_v2
flutter pub get
flutter run
```

### Build

```bash
# Android APK
flutter build apk --release

# iOS (auf Mac)
flutter build ios --release
```

## Validierungslogik

Die Validierung ist aktuell als Dummy implementiert - der Benutzer wählt manuell, ob eine Messung gültig oder ungültig ist. Die automatische Validierungslogik kann später im `MeasurementValidationService` implementiert werden.

## Protokoll-Felder

Das generierte PDF enthält:

- Projektinformationen (Objekt, Projekt, Verfasser)
- Druckprüfung (Betriebsdruck, Prüfdruck, Prüfdauer)
- Prüfart (Optisch, Lecksuchspray, Röntgenprüfung, Vakuumtest)
- Resultat (Bestanden/Nicht bestanden)
- Druckverlauf-Kurve
- Messdaten-Zusammenfassung
- Datum und Unterschrift des Monteurs

## Lizenz

Proprietär - Soleco AG
