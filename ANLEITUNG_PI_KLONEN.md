# Prezio Recorder - SD-Karte vorbereiten & klonen

**Stand:** Maerz 2026  
**Ziel:** Einen neuen Prezio Recorder (Raspberry Pi Zero 2 W oder Pi 4B) in Betrieb nehmen oder einen bestehenden klonen.

---

## Methode 1: PrezioImager (empfohlen - vollautomatisch)

Der **PrezioImager** ist das einfachste Werkzeug um neue SD-Karten fuer Prezio Recorder vorzubereiten. Er ist im PrezioHub Installer enthalten. Die gesamte Einrichtung (WiFi AP, SSH, Recorder-Service) passiert automatisch - man muss nur die Karte flashen und den Pi einschalten.

### Voraussetzungen

- Windows-PC mit SD-Kartenleser
- Leere microSD-Karte (mind. 16 GB, empfohlen 32 GB)
- PrezioHub installiert (oder PrezioImager.exe direkt)
- **Internetverbindung** (zum Herunterladen des OS-Images beim ersten Mal und fuer die Firmware)

### Schritt fuer Schritt

1. **PrezioImager starten** (aus PrezioHub > Tools > PrezioImager, oder direkt die .exe)
   - Benoetigt Admin-Rechte (UAC-Dialog bestaetigen)
   - Der Imager laedt automatisch die neueste Firmware von GitHub
   - Falls kein Internet: lokaler Cache wird genutzt (max. 24h alt)

2. **SD-Karte einlegen** und im PrezioImager auswaehlen
   - PrezioImager erkennt verfuegbare SD-Karten automatisch
   - **Achtung:** Alle Daten auf der Karte werden unwiderruflich geloescht!

3. **"Flash starten"** klicken
   - PrezioImager laedt das Raspberry Pi OS Lite (64-bit) automatisch herunter (ca. 500 MB, nur beim ersten Mal)
   - Formatiert und flasht die SD-Karte
   - Kopiert die Firmware-Dateien auf die Karte (`pi_recorder.py`, `setup_pi.sh`, `requirements.txt`, `howto.txt`, `pyserial`)
   - Erstellt ein Erststart-Script (`firstrun.sh`) fuer den automatischen Setup

4. **SD-Karte in den Pi einsetzen und Strom anschliessen**
   - KELLER LEO5 per USB-OTG (Pi Zero) oder USB-A (Pi 4) anschliessen
   - Strom anschliessen

5. **3-5 Minuten warten** (wichtig! Nicht zu frueh abschalten!)
   - Der Pi durchlaeuft einen automatischen 2-Phasen-Boot:

   | Phase | Was passiert |
   |-------|-------------|
   | **Phase 1** (erster Boot, ~60s) | User `pi` wird erstellt, SSH aktiviert, Firmware-Dateien kopiert, Setup-Service fuer Phase 2 erstellt, **automatischer Reboot** |
   | **Phase 2** (zweiter Boot, ~60-120s) | WiFi-Country auf CH gesetzt, WiFi freigeschaltet, NetworkManager gewartet, WiFi AP "Prezio-Recorder" konfiguriert, Python + pyserial installiert, Recorder-Service installiert und gestartet |

6. **WiFi "Prezio-Recorder" sollte sichtbar sein**
   - Passwort: `prezio2026`
   - Pi-IP: `192.168.4.1`

7. **Testen**
   - Handy/PC mit "Prezio-Recorder" WiFi verbinden
   - Im Browser: `http://192.168.4.1:8080/health`
   - Sollte JSON mit Sensorstatus zeigen
   - In der Prezio-App: Automatische Verbindung

### Dauer

Komplett ca. **10-15 Minuten** (inkl. Download beim ersten Mal).

### Firmware-Cache

Der PrezioImager verwendet denselben Firmware-Cache wie der PrezioHub:
- **Pfad:** `%LOCALAPPDATA%\PrezioHub\firmware_cache\`
- **Mit Internet:** Immer die neueste Version von GitHub geladen
- **Ohne Internet:** Lokaler Cache wird genutzt, sofern weniger als 24 Stunden alt
- **Ohne Internet + Cache aelter als 24h:** Fehlermeldung - bitte mit Internet starten

**Tipp:** PrezioHub einmal mit Internet starten, bevor man den Imager verwendet. Dann ist der Cache immer aktuell.

---

## Methode 2: Bestehendes Image klonen (manuell)

Falls der PrezioImager nicht verfuegbar ist oder du ein bestehendes, angepasstes System sichern/klonen willst.

### Image vom fertigen Pi erstellen

#### Schritt 1 - Pi herunterfahren

Per SSH (verbunden mit Pi-WLAN):

```
ssh pi@192.168.4.1
sudo shutdown -h now
```

Warten bis die gruene LED aufhoert zu blinken (~10 Sekunden).

#### Schritt 2 - SD-Karte in den PC einlegen

- SD-Karte herausnehmen
- In den Kartenleser am Windows-PC stecken
- Formatierungsdialog mit **Nein / Abbrechen** beantworten!

#### Schritt 3 - Image lesen (Win32 Disk Imager)

1. **Win32 Disk Imager** herunterladen: https://sourceforge.net/projects/win32diskimager/
2. Als Administrator starten
3. **Device:** Laufwerksbuchstabe der SD-Karte waehlen
4. **Image File:** Speicherort waehlen, z.B. `prezio_recorder_v1.img`
5. **Read** klicken (dauert 10-20 Min. bei 32 GB)

#### Schritt 4 - Image verkleinern (optional, empfohlen)

Das Image ist so gross wie die gesamte SD-Karte. Mit **PiShrink** wird es auf die tatsaechliche Groesse geschrumpft:

```bash
# In WSL (Windows Subsystem for Linux):
wget https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh
chmod +x pishrink.sh
sudo mv pishrink.sh /usr/local/bin/

cp /mnt/c/Users/noegl/Desktop/prezio_recorder_v1.img ~/prezio_recorder_v1.img
sudo pishrink.sh -z ~/prezio_recorder_v1.img
cp ~/prezio_recorder_v1.img.gz /mnt/c/Users/noegl/Desktop/
```

Ergebnis: statt 32 GB eine komprimierte `.img.gz` von ca. 1-3 GB.

### Image auf neue SD-Karte schreiben

#### Mit Raspberry Pi Imager (einfacher)

1. Raspberry Pi Imager herunterladen: https://www.raspberrypi.com/software/
2. "Eigenes Image verwenden" waehlen
3. `.img` oder `.img.gz` Datei auswaehlen
4. SD-Karte als Ziel waehlen
5. **NICHT** auf Einstellungen klicken - keine Anpassungen!
6. "Schreiben" klicken

#### Mit Win32 Disk Imager

1. **Image File:** Die `.img`-Datei auswaehlen (`.img.gz` muss vorher entpackt werden)
2. **Device:** Neue SD-Karte auswaehlen
3. **Write** klicken

---

## Methode 3: Manuelle Einrichtung (Fallback)

Falls weder PrezioImager noch ein bestehendes Image verfuegbar ist. Erfordert SSH-Zugang und Internetzugang auf dem Pi.

### Ablauf

1. **SD-Karte** mit dem offiziellen Raspberry Pi Imager flashen:
   - OS: Raspberry Pi OS Lite (64-bit)
   - Hostname: `prezio-recorder`
   - SSH aktivieren, User: `pi`, Passwort: `Prezio2000!`
   - **WiFi: Buero-/Heim-WLAN eintragen** (fuer Ersteinrichtung mit Internet)

2. **Pi starten** und per SSH verbinden:
   ```bash
   ssh pi@prezio-recorder.local
   ```

3. **Software installieren:**
   ```bash
   sudo apt update && sudo apt install -y git python3-pip python3-venv
   cd /home/pi
   git clone https://github.com/someFisherman/prezio-v2.git
   cd prezio-v2/pi_recorder
   sudo bash setup_pi.sh
   ```

4. **Neustart:**
   ```bash
   sudo reboot
   ```

5. **Testen:** WiFi "Prezio-Recorder" suchen, verbinden, `http://192.168.4.1:8080/health` pruefen.

Ab jetzt hat der Pi sein eigenes WiFi und braucht kein Buero-WLAN mehr.

---

## Hardware-Info: Pi Zero 2 W

### Einkaufsliste

| Teil | Preis ca. |
|------|-----------|
| Raspberry Pi Zero 2 W | CHF 20 |
| microSD 32 GB (Class 10) | CHF 10 |
| USB-OTG-Adapter (Micro-USB auf USB-A) | CHF 5 |
| USB-Seriell-Adapter (fuer KELLER LEO5) | CHF 15 |
| Micro-USB-Netzteil (5V / 2A) | CHF 15 |

### Zusammenbau

1. microSD in den Pi Zero 2 W einsetzen
2. USB-OTG-Adapter an den **Daten-Micro-USB** (rechts, neben HDMI) anschliessen
3. USB-Seriell-Adapter mit KELLER LEO5 verbinden
4. USB-Seriell-Adapter an den OTG-Adapter stecken
5. Micro-USB-Netzteil an den **Power-Port** (links, aussen) anschliessen

**WICHTIG:** Beim Pi Zero 2 W gibt es zwei Micro-USB-Ports:
- **Links (aussen):** Nur Strom
- **Rechts (neben HDMI):** Daten (hier den OTG-Adapter)

### Pi 4 B vs. Pi Zero 2 W

| Eigenschaft | Pi 4 B | Pi Zero 2 W |
|---|---|---|
| USB-Ports | 4x USB-A | 1x Micro-USB (OTG) |
| WiFi | 2.4 + 5 GHz | 2.4 GHz |
| Leistung | Mehr als genug | Voellig ausreichend |
| Stromverbrauch | ~3-7W | ~1-2W |
| Preis | ~CHF 50-80 | ~CHF 20 |
| OTG-Adapter noetig? | Nein | Ja |

---

## Hinweise

### Alle Klone sind identisch

Jeder geklonte/geflashte Pi hat dieselbe SSID ("Prezio-Recorder"), denselben Key und dieselbe IP (192.168.4.1). Das ist kein Problem, solange nicht zwei Recorder gleichzeitig am selben Ort eingeschaltet sind.

### Pi-Firmware aktuell halten

Wenn eine neue Version von `pi_recorder.py` verfuegbar ist:
1. PrezioHub mit Internet starten (Cache wird aktualisiert)
2. Mit Pi-WiFi verbinden
3. Dashboard zeigt oranges Banner "UPDATE FAELLIG"
4. In Pi-Steuerung → "Jetzt updaten" klicken
5. Fertig - kein Neufashen der SD-Karte noetig

### SSH-Zugang nach dem Flashen

Falls du nach dem Flashen per SSH auf den Pi zugreifen willst:

```bash
# Mit dem Pi-WiFi "Prezio-Recorder" verbinden, dann:
ssh pi@192.168.4.1
# Passwort: Prezio2000!

# Falls "HOST IDENTIFICATION HAS CHANGED" Fehler:
ssh-keygen -R 192.168.4.1
ssh-keygen -R prezio-recorder.local
```

### Fehlerbehebung: WiFi erscheint nicht

| Problem | Loesung |
|---------|---------|
| WiFi nach 5 Min. nicht sichtbar | Pi per Ethernet anschliessen, per SSH Logs pruefen |
| Logs pruefen | `ssh pi@prezio-recorder.local` dann `cat /var/log/prezio-firstboot.log` |
| Setup-Service Status | `sudo systemctl status prezio-setup.service` |
| Manuell ausfuehren | `cd /home/pi/prezio-v2/pi_recorder && sudo bash setup_pi.sh` |

---

*Stand: Maerz 2026 - Soleco AG*
