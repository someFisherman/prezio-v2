# Prezio Recorder - SD-Karte vorbereiten & klonen

**Stand:** Maerz 2026  
**Ziel:** Einen neuen Prezio Recorder (Raspberry Pi Zero 2 W) in Betrieb nehmen oder einen bestehenden klonen.

---

## Methode 1: PrezioImager (empfohlen)

Der **PrezioImager** ist das einfachste Werkzeug um neue SD-Karten fuer Prezio Recorder vorzubereiten. Er ist im PrezioHub Installer enthalten.

### Voraussetzungen

- Windows-PC mit SD-Kartenleser
- Leere microSD-Karte (mind. 16 GB, empfohlen 32 GB)
- PrezioHub installiert (oder PrezioImager.exe direkt)

### Schritt fuer Schritt

1. **PrezioImager starten** (aus PrezioHub > Tools > PrezioImager, oder direkt die .exe)
   - Benoetigt Admin-Rechte (UAC-Dialog bestaetigen)

2. **SD-Karte einlegen** und im PrezioImager auswaehlen
   - PrezioImager erkennt verfuegbare SD-Karten automatisch
   - **Achtung:** Alle Daten auf der Karte werden geloescht!

3. **"Flash starten"** klicken
   - PrezioImager laedt das Raspberry Pi OS automatisch herunter (beim ersten Mal)
   - Bereitet die Karte vor (Partitionen, Dateisystem)
   - Flasht das Image auf die Karte
   - Richtet SSH, WiFi AP und den Prezio Service automatisch ein

4. **SD-Karte einlegen und Pi starten**
   - microSD in den Pi Zero 2 W einsetzen
   - KELLER LEO5 per USB-OTG anschliessen
   - Strom anschliessen
   - ~60 Sekunden warten
   - WiFi "Prezio-Recorder" sollte sichtbar sein

5. **Testen**
   - Handy mit "Prezio-Recorder" WiFi verbinden (Passwort: `prezio2026`)
   - Im Browser: `http://192.168.4.1:8080/health`
   - Sollte JSON mit Sensorstatus zeigen

### Dauer

Komplett ca. **10-15 Minuten** (inkl. Download beim ersten Mal).

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

Jeder Klon hat dieselbe SSID ("Prezio-Recorder"), denselben Key und dieselbe IP (192.168.4.1). Das ist kein Problem, solange nicht zwei Recorder gleichzeitig am selben Ort eingeschaltet sind.

### Image-Versionierung

```
prezio_recorder_v1.img.gz    (Erstversion)
prezio_recorder_v2.img.gz    (nach Update)
```

### Checkliste vor dem Image-Erstellen

- [ ] WiFi AP startet automatisch ("Prezio-Recorder", 192.168.4.1)
- [ ] `prezio-recorder.service` startet automatisch
- [ ] Auth-Key wird korrekt ausgeliefert
- [ ] Aufzeichnung starten/stoppen funktioniert
- [ ] Keine persoenlichen Daten oder Test-Messungen auf der Karte

---

*Stand: Maerz 2026 - Soleco AG*
