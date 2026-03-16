# Prezio Recorder - Raspberry Pi Klonen (Image-Anleitung)

**Stand:** Maerz 2026  
**Ziel:** Einen fertig konfigurierten Prezio Recorder (Raspberry Pi) als Image sichern und beliebig oft auf neue SD-Karten klonen.

---

## Voraussetzungen

- Ein **fertig eingerichteter Raspberry Pi** (Prezio Recorder laeuft, WLAN-AP aktiv, Sensor funktioniert)
- Windows-PC mit SD-Karten-Leser
- **Win32 Disk Imager** (gratis): https://sourceforge.net/projects/win32diskimager/
- Optional: **WSL** (Windows Subsystem for Linux) fuer PiShrink zum Verkleinern des Images
- Leere SD-Karten fuer die Klone (mind. gleich gross wie die Original-Karte)

---

## Teil 1: Image vom fertigen Pi erstellen

### Schritt 1 - Pi herunterfahren

Per SSH (vom Handy/PC, verbunden mit dem Pi-WLAN):

```
ssh pi@192.168.4.1
sudo shutdown -h now
```

Warten bis die gruene LED aufhoert zu blinken (ca. 10 Sekunden).

### Schritt 2 - SD-Karte entnehmen

- Strom vom Pi trennen
- SD-Karte vorsichtig herausziehen

### Schritt 3 - SD-Karte in den PC einlegen

- SD-Karte in den Kartenleser am Windows-PC stecken
- Windows zeigt evtl. ein Popup "Moechten Sie formatieren?" → **NEIN / Abbrechen** klicken!
- Merke dir den Laufwerksbuchstaben (z.B. `D:` oder `E:`)

### Schritt 4 - Win32 Disk Imager oeffnen

1. Win32 Disk Imager starten (**als Administrator**)
2. Oben rechts bei **Device**: Den Laufwerksbuchstaben der SD-Karte auswaehlen (z.B. `D:`)
3. Oben links bei **Image File**: Einen Speicherort waehlen, z.B.:
   ```
   C:\Users\noegl\Desktop\prezio_recorder_v1.img
   ```
4. Auf **Read** klicken
5. Warten bis der Vorgang abgeschlossen ist (bei 32 GB ca. 10-20 Minuten)
6. Fertig - du hast jetzt ein vollstaendiges Abbild der SD-Karte

### Schritt 5 - SD-Karte zurueck in den Pi

- SD-Karte sicher auswerfen (Rechtsklick im Explorer → "Auswerfen")
- Zurueck in den Pi stecken
- Strom anschliessen - Pi laeuft wieder wie vorher

---

## Teil 2: Image verkleinern (empfohlen)

Das Image ist so gross wie die gesamte SD-Karte (z.B. 32 GB), obwohl nur 2-4 GB tatsaechlich belegt sind. Mit **PiShrink** wird es auf die tatsaechliche Groesse geschrumpft.

### Schritt 6 - WSL installieren (falls noch nicht vorhanden)

In PowerShell als Administrator:

```powershell
wsl --install
```

PC neu starten, Ubuntu-Benutzername und Passwort festlegen.

### Schritt 7 - PiShrink installieren

In WSL (Ubuntu-Terminal):

```bash
wget https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh
chmod +x pishrink.sh
sudo mv pishrink.sh /usr/local/bin/
```

### Schritt 8 - Image verkleinern

In WSL das Windows-Image ansprechen (Windows-Laufwerke sind unter `/mnt/c/` erreichbar):

```bash
# Image kopieren nach WSL (schneller als direkt auf /mnt/ zu arbeiten)
cp /mnt/c/Users/noegl/Desktop/prezio_recorder_v1.img ~/prezio_recorder_v1.img

# PiShrink ausfuehren
sudo pishrink.sh -z ~/prezio_recorder_v1.img

# Ergebnis zurueck nach Windows kopieren
cp ~/prezio_recorder_v1.img.gz /mnt/c/Users/noegl/Desktop/
```

**Ergebnis:** Statt 32 GB hast du jetzt eine komprimierte `.img.gz`-Datei von ca. 1-3 GB.

> **Hinweis:** Die Option `-z` komprimiert das Image zusaetzlich mit gzip. Beim Flashen mit balenaEtcher oder Raspberry Pi Imager kann die `.img.gz` direkt verwendet werden (ohne vorheriges Entpacken).

---

## Teil 3: Image auf neue SD-Karte brennen (Klonen)

### Schritt 9 - Neue SD-Karte einlegen

- Leere SD-Karte (mind. 8 GB, empfohlen 16 GB) in den Kartenleser stecken
- Wieder: Formatierungsdialog mit **Nein** beantworten

### Schritt 10a - Mit Win32 Disk Imager brennen

1. Win32 Disk Imager oeffnen (**als Administrator**)
2. **Image File**: Die `.img`-Datei auswaehlen (nicht die `.img.gz` - die muss vorher entpackt werden)
3. **Device**: Neue SD-Karte auswaehlen
4. Auf **Write** klicken
5. Sicherheitsabfrage bestaetigen
6. Warten bis fertig (ca. 5-15 Minuten)

### Schritt 10b - Alternativ: Mit Raspberry Pi Imager brennen (einfacher)

1. **Raspberry Pi Imager** herunterladen: https://www.raspberrypi.com/software/
2. Oeffnen
3. Bei "Betriebssystem": Ganz unten **"Eigenes Image verwenden"** waehlen
4. Die `.img` oder `.img.gz` Datei auswaehlen
5. SD-Karte als Ziel waehlen
6. **WICHTIG:** NICHT auf das Zahnrad/Einstellungen klicken - keine Anpassungen vornehmen, sonst wird die Konfiguration ueberschrieben!
7. Auf **Schreiben** klicken
8. Warten bis fertig

### Schritt 11 - Neuen Pi starten

- SD-Karte in den neuen Raspberry Pi Zero 2 W einlegen
- Strom anschliessen
- Warten ca. 30-60 Sekunden
- Das WLAN "Prezio Recorder" sollte erscheinen
- Handy verbinden und testen

---

## Teil 4: Hinweise und Tipps

### Kompatibilitaet Pi 4B vs. Pi Zero 2 W

Raspberry Pi OS ist grundsaetzlich kompatibel zwischen den Modellen. **Allerdings:**

| Thema | Empfehlung |
|---|---|
| Kernel | Beide nutzen arm64 - kompatibel |
| WLAN-Chip | Unterschiedlich, aber Treiber sind im OS enthalten |
| Performance | Zero 2 W ist langsamer, funktioniert aber fuer Prezio |
| **Bester Weg** | **Image direkt auf einem Zero 2 W erstellen**, dann gibt es null Probleme |

Wenn du das Image auf dem Pi 4B erstellst und auf dem Zero 2 W nutzt, sollte es funktionieren. Falls es Probleme gibt (was selten ist), einmalig den Zero 2 W manuell einrichten und dann davon das Image ziehen.

### Alle Klone sind identisch

Jeder Klon hat:
- Denselben WLAN-Namen ("Prezio Recorder")
- Denselben Auth-Key
- Dieselbe IP-Adresse (192.168.4.1)
- Denselben SSH-Zugang (pi / dein Passwort)

Das ist **kein Problem**, solange nicht zwei Prezio Recorder gleichzeitig am selben Ort eingeschaltet sind.

### Image aktualisieren

Wenn du spaeter die Software aktualisierst (z.B. neues `pi_recorder.py`):

1. Einen Pi mit dem alten Image starten
2. Per SSH verbinden und Aenderungen machen
3. Testen
4. Neues Image ziehen (Schritte 1-8 wiederholen)
5. Altes Image umbenennen oder loeschen

Empfohlene Benennung:

```
prezio_recorder_v1.img.gz    (Erstversion)
prezio_recorder_v2.img.gz    (nach Update)
prezio_recorder_v3.img.gz    (...)
```

### Checkliste vor dem Image-Erstellen

Bevor du das finale Image erstellst, stelle sicher:

- [ ] WLAN-Accesspoint startet automatisch ("Prezio Recorder", 192.168.4.1)
- [ ] `prezio-recorder.service` startet automatisch (`systemctl is-enabled prezio-recorder`)
- [ ] Auth-Key wird korrekt ausgeliefert (`curl http://192.168.4.1:5000/auth/key`)
- [ ] Aufzeichnung starten/stoppen funktioniert
- [ ] Messdaten werden korrekt gespeichert und abrufbar
- [ ] Max. 10 Messungen, aelteste wird geloescht
- [ ] Reboot-Befehl funktioniert (`curl -X POST http://192.168.4.1:5000/reboot`)
- [ ] SSH-Passwort ist bekannt und dokumentiert
- [ ] Keine persoenlichen Daten / Test-Messungen auf der Karte

### Speicherort fuer das Image

Empfohlen:
- **Lokal:** `C:\Users\noegl\Desktop\prezio_images\`
- **Cloud:** Im GitHub-Repository unter "Releases" (bis 2 GB pro Datei moeglich)
- **Alternativ:** Supabase Storage, OneDrive, oder USB-Stick im Buero

---

## Kurzanleitung (Zusammenfassung)

```
NEUEN PREZIO RECORDER BAUEN:
============================
1. Raspberry Pi Imager oeffnen
2. "Eigenes Image" → prezio_recorder_vX.img.gz waehlen
3. SD-Karte waehlen → Schreiben
4. SD-Karte in Pi Zero 2 W einlegen
5. KELLER LEO5 Sensor per USB anschliessen
6. Strom anschliessen
7. 60 Sekunden warten
8. "Prezio Recorder" WLAN sollte sichtbar sein
9. Mit Prezio App verbinden → Fertig
```

Geschaetzte Zeit pro neuem Geraet: **~15 Minuten** (davon 10 Min. Image brennen).
