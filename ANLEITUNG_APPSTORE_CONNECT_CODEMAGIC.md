# App Store Connect API + Codemagic – Schritt-für-Schritt

Diese Anleitung erklärt, wie du dein Apple Developer Konto (gloognoe@gmail.com) mit Codemagic verbindest, damit die Prezio-App automatisch signiert und als IPA gebaut werden kann.

---

## Voraussetzungen

- [ ] Apple Developer Program Mitgliedschaft (99 USD/Jahr)
- [ ] Codemagic-Konto (kostenlos oder bezahlt)
- [ ] Zugriff auf [App Store Connect](https://appstoreconnect.apple.com) und [Apple Developer Portal](https://developer.apple.com/account)

---

## Teil 1: App Store Connect API Key erstellen

Der API Key erlaubt Codemagic, Zertifikate und Provisioning Profiles in deinem Namen zu verwalten.

### Schritt 1.1: App Store Connect öffnen

1. Gehe zu **https://appstoreconnect.apple.com**
2. Melde dich mit **gloognoe@gmail.com** an (oder dem Konto, das mit deinem Developer Account verknüpft ist)

### Schritt 1.2: API Keys anlegen

1. Klicke oben rechts auf deinen **Namen** (oder das Avatar-Icon)
2. Wähle **Users and Access**
3. Klicke oben auf den Tab **Integrations**
4. Wähle **App Store Connect API**
5. Klicke auf **+** (Plus) um einen neuen Key zu erstellen

### Schritt 1.3: Key konfigurieren

1. **Name:** z.B. `Codemagic Prezio` (oder ein beliebiger Name)
2. **Access:** Wähle **App Manager** (empfohlen für CI/CD)
3. Klicke auf **Generate**

### Schritt 1.4: Key-Daten notieren

1. **Issuer ID:** Steht oben über der Tabelle der Keys – **notieren und kopieren**
2. **Key ID:** Wird nach dem Erstellen angezeigt – **notieren und kopieren**
3. **Download API Key:** Klicke auf **Download API Key** – es erscheint eine `.p8` Datei
   - **Wichtig:** Diese Datei kann nur **einmal** heruntergeladen werden!
   - Speichere sie sicher (z.B. `AuthKey_XXXXXXXXXX.p8`)

---

## Teil 2: App-ID im Apple Developer Portal prüfen

Die Prezio-App braucht die Bundle-ID `ch.soleco.prezioV2`.

### Schritt 2.1: Developer Portal öffnen

1. Gehe zu **https://developer.apple.com/account**
2. Melde dich an

### Schritt 2.2: App-ID prüfen / anlegen

1. Gehe zu **Certificates, Identifiers & Profiles**
2. Klicke links auf **Identifiers**
3. Prüfe, ob `ch.soleco.prezioV2` (ohne Zusatz) existiert
4. **Falls nicht** – neue App-ID anlegen:

---

#### App-ID `ch.soleco.prezioV2` anlegen (Schritt für Schritt)

1. **+** (Plus-Button oben rechts) klicken

2. **Register an identifier** → **App IDs** auswählen → **Continue**

3. **Type:** **App** auswählen (nicht App Clip, nicht andere Typen) → **Continue**

4. **Description:** z.B. `Prezio` (nur zur Anzeige, beliebig)

5. **Bundle ID:**
   - **Explicit** auswählen (nicht Wildcard)
   - Im Feld darunter eintragen: `ch.soleco.prezioV2`

6. **Capabilities** (optional – für Prezio reicht Standard):
   - **Nichts ankreuzen** für einen minimalen Start
   - Oder falls nötig:
     - **Location** (wenn GPS genutzt wird – Prezio nutzt Standort)
     - **Local Network** (für Verbindung zum Raspberry Pi / Recorder)
   - **5G, App Clips, etc.** – nicht nötig

7. **Continue** → **Register** klicken

Fertig. Die App-ID `ch.soleco.prezioV2` existiert jetzt und kann für Provisioning Profiles verwendet werden.

---

## Teil 3: Codemagic – API Key hinzufügen

### Schritt 3.1: Codemagic öffnen

1. Gehe zu **https://codemagic.io**
2. Melde dich an

### Schritt 3.2: Team-Einstellungen

1. Klicke oben rechts auf deinen **Namen** oder **Team-Namen**
2. Wähle **Team settings** (oder **Personal account** bei Einzelprojekten)
3. Gehe zu **Integrations** → **Developer Portal**

### Schritt 3.3: App Store Connect API Key hinzufügen

1. Klicke auf **Manage keys** (oder **Add key**)
2. **App Store Connect API key name:** z.B. `Prezio` (nur zur Identifikation)

3. **Issuer ID:** Wert aus Schritt 1.4 einfügen

4. **Key ID:** Wert aus Schritt 1.4 einfügen

5. **API key:** Die `.p8` Datei hochladen (Drag & Drop oder **Choose a .p8 file**)

6. **Save** klicken

---

## Teil 4: Codemagic – Code Signing Identities

### Schritt 4.1: Code Signing Identities öffnen

1. In **Team settings** → **codemagic.yaml settings** → **Code signing identities**
2. Oder: App auswählen → **Settings** → **Code signing identities**

### Schritt 4.2: Zertifikat

**Option A – Automatisch generieren (empfohlen):**

1. Tab **iOS certificates**
2. **Create certificate** → **Generate new certificate**
3. **App Store Connect API key:** Deinen Key auswählen (z.B. `Prezio`)
4. **Certificate type:** `Apple Distribution` (für App Store / TestFlight)
5. **Reference name:** z.B. `prezio_distribution`
6. **Generate certificate** klicken
7. Zertifikat und Passwort **einmalig** herunterladen und speichern
8. **Upload certificate** (gleicher Tab) → `.p12` hochladen, Passwort eingeben, Reference name z.B. `prezio_distribution`

**Option B – Manuell hochladen:**

1. Zertifikat mit Xcode aus Keychain exportieren (`.p12`)
2. **Upload certificate** → Datei hochladen, Passwort eingeben, Reference name vergeben

### Schritt 4.3: Provisioning Profile

**Option A – Vom Developer Portal holen:**

1. Tab **iOS provisioning profiles**
2. **Fetch profiles** → **Fetch from Developer Portal**
3. App Store Connect API Key auswählen
4. Unter **App Store profiles** das passende Profil für `ch.soleco.prezioV2` auswählen
5. **Reference name:** z.B. `prezio_appstore`
6. **Download selected** klicken

**Option B – Manuell hochladen:**

1. Im [Apple Developer Portal](https://developer.apple.com/account/resources/profiles/list) ein Provisioning Profile für `ch.soleco.prezioV2` erstellen (Typ: App Store)
2. **Add profile** → `.mobileprovision` hochladen, Reference name vergeben

---

## Teil 5: codemagic.yaml prüfen

Die `codemagic.yaml` ist bereits für die App-ID konfiguriert:

```yaml
environment:
  ios_signing:
    distribution_type: app_store
    bundle_identifier: ch.soleco.prezioV2
```

**Wichtig:** Mit `distribution_type` und `bundle_identifier` holt Codemagic automatisch alle passenden Zertifikate und Profiles aus den Code Signing Identities. Du musst keine Reference Names in der YAML angeben.

---

## Teil 6: Ersten Build starten

1. In Codemagic: **Apps** → **Prezio** (oder deine App) auswählen
2. Workflow **iOS Build (Signed)** oder **Build All** wählen
3. **Start new build** klicken

---

## Teil 7: App in App Store Connect anlegen (für TestFlight/App Store)

Falls die App noch nicht in App Store Connect existiert:

1. **https://appstoreconnect.apple.com** → **My Apps**
2. **+** → **New App**
3. **Platform:** iOS
4. **Name:** Prezio
5. **Primary language:** Deutsch (Schweiz) oder Deutsch
6. **Bundle ID:** `ch.soleco.prezioV2` auswählen
7. **SKU:** z.B. `prezio-v2`
8. **Create** klicken

---

## Teil 8: TestFlight / App Store (optional)

Für automatisches Hochladen in TestFlight:

1. In Codemagic: **Publishing** → **App Store Connect** hinzufügen
2. **App Store Connect API key** (gleicher Key wie oben)

Die `codemagic.yaml` kann um einen Publishing-Schritt erweitert werden, z.B.:

```yaml
publishing:
  app_store_connect:
    api_key: Prezio  # oder der Name deines Keys
    submit_to_testflight: true
```

---

## Troubleshooting

| Problem | Lösung |
|--------|--------|
| "Key not found" | API Key in Codemagic richtig hochgeladen? Issuer ID + Key ID prüfen |
| "No matching provisioning profile" | Bundle ID `ch.soleco.prezioV2` im Developer Portal angelegt? App-Store-Provisioning-Profile erstellt und in Codemagic hochgeladen? |
| "Certificate not in profile" | Zertifikat und Provisioning Profile müssen vom gleichen Team/Account stammen |
| "Development Team required" | API Key in Codemagic verbunden? Code Signing Identities ausgefüllt? |
| **Keine IPA in Codemagic** | Build-Logs prüfen: Schlägt "xcode-project use-profiles" oder "flutter build ipa" fehl? Provisioning Profile + Zertifikat in Codemagic hochgeladen? Workflow "iOS Build (Signed)" verwenden. |
| **Keine IPA auf TestFlight** | 1) App in App Store Connect angelegt? 2) In Codemagic: App → Workflow → **Publishing** → **App Store Connect** hinzufügen, API Key verknüpfen, App ID eintragen. 3) Oder IPA manuell mit Transporter-App hochladen. |

---

## Checkliste

- [ ] App Store Connect API Key erstellt (.p8 gespeichert)
- [ ] Issuer ID + Key ID notiert
- [ ] API Key in Codemagic (Team settings) hinzugefügt
- [ ] Zertifikat in Codemagic (generiert oder hochgeladen)
- [ ] Provisioning Profile in Codemagic (geholt oder hochgeladen)
- [ ] Bundle ID `ch.soleco.prezioV2` im Developer Portal vorhanden
- [ ] codemagic.yaml mit `ios_signing` und `bundle_identifier` konfiguriert
- [ ] App in App Store Connect angelegt (für TestFlight/Store)

---

*Stand: März 2026*
