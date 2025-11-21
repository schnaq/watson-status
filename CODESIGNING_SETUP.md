# macOS Code Signing und Notarisierung für CI/CD

Diese Anleitung erklärt, wie du die notwendigen Secrets für die automatische Signierung und Notarisierung der WatsonStatus macOS App in GitHub Actions einrichtest.

## Voraussetzungen

Du benötigst:
- Einen **Apple Developer Account** (99 USD/Jahr) unter dem schnaq Account
- Zugang zum **Apple Developer Portal** (https://developer.apple.com)
- Zugang zu einem Mac mit Xcode installiert (für die initiale Zertifikatserstellung)

---

## Schritt 1: Developer ID Application Zertifikat erstellen

### 1.1 Zertifikat im Apple Developer Portal erstellen

1. Gehe zu https://developer.apple.com/account/resources/certificates/list
2. Melde dich mit dem schnaq Apple Developer Account an
3. Klicke auf das **"+"** Symbol, um ein neues Zertifikat zu erstellen
4. Wähle **"Developer ID Application"** (unter "Software" Kategorie)
5. Klicke auf **Continue**

### 1.2 Certificate Signing Request (CSR) erstellen

Auf deinem Mac:

1. Öffne **Keychain Access** (Schlüsselbundverwaltung)
2. Gehe zu **Keychain Access > Certificate Assistant > Request a Certificate From a Certificate Authority**
3. Fülle aus:
   - **User Email Address**: Deine schnaq E-Mail
   - **Common Name**: "schnaq WatsonStatus Signing"
   - **CA Email Address**: Leer lassen
   - Wähle: **"Saved to disk"**
4. Klicke auf **Continue** und speichere die CSR-Datei

### 1.3 Zertifikat herunterladen und installieren

1. Lade die CSR-Datei im Apple Developer Portal hoch
2. Klicke auf **Continue**
3. Lade das erstellte Zertifikat herunter (`.cer` Datei)
4. Doppelklicke die `.cer` Datei, um sie in Keychain Access zu installieren

### 1.4 Zertifikat als .p12 exportieren

1. Öffne **Keychain Access**
2. Wähle den Keychain **"login"** und Kategorie **"My Certificates"**
3. Finde das Zertifikat "Developer ID Application: [Dein Name] ([Team ID])"
4. Rechtsklick → **Export**
5. Speichere als `.p12` Datei
6. **Setze ein starkes Passwort** (merken für später!)
7. Gib dein Mac-Passwort ein, um den Export zu autorisieren

---

## Schritt 2: App-Specific Password erstellen

Für die Notarisierung benötigst du ein App-Specific Password:

1. Gehe zu https://appleid.apple.com
2. Melde dich mit dem schnaq Apple Developer Account an
3. Gehe zum Bereich **"Sign-In and Security"** → **"App-Specific Passwords"**
4. Klicke auf **"Generate an app-specific password"**
5. Name: `GitHub Actions Notarization`
6. **Kopiere das generierte Passwort** (sieht aus wie: `abcd-efgh-ijkl-mnop`)

---

## Schritt 3: Team ID herausfinden

1. Gehe zu https://developer.apple.com/account
2. Unter **Membership Details** findest du die **Team ID**
3. Es ist eine 10-stellige alphanumerische ID (z.B. `A1B2C3D4E5`)

---

## Schritt 4: GitHub Secrets einrichten

### 4.1 .p12 Zertifikat zu Base64 konvertieren

Auf deinem Mac, im Terminal:

```bash
# Konvertiere .p12 zu Base64
base64 -i /Pfad/zu/deinem/Zertifikat.p12 | pbcopy
```

Das Zertifikat ist jetzt in deiner Zwischenablage als Base64-String.

### 4.2 Secrets in GitHub hinterlegen

1. Gehe zu deinem GitHub Repository: https://github.com/schnaq/watson-status
2. Klicke auf **Settings** → **Secrets and variables** → **Actions**
3. Klicke auf **"New repository secret"** und füge folgende Secrets hinzu:

#### Secret 1: `APPLE_CERTIFICATE_BASE64`
- **Name**: `APPLE_CERTIFICATE_BASE64`
- **Value**: Füge den Base64-String aus deiner Zwischenablage ein
- Klicke auf **Add secret**

#### Secret 2: `APPLE_CERTIFICATE_PASSWORD`
- **Name**: `APPLE_CERTIFICATE_PASSWORD`
- **Value**: Das Passwort, das du beim Export der .p12 Datei gesetzt hast
- Klicke auf **Add secret**

#### Secret 3: `APPLE_ID`
- **Name**: `APPLE_ID`
- **Value**: Die Apple ID E-Mail-Adresse des schnaq Developer Accounts
- Klicke auf **Add secret**

#### Secret 4: `APPLE_APP_SPECIFIC_PASSWORD`
- **Name**: `APPLE_APP_SPECIFIC_PASSWORD`
- **Value**: Das App-Specific Password aus Schritt 2
- Klicke auf **Add secret**

#### Secret 5: `APPLE_TEAM_ID`
- **Name**: `APPLE_TEAM_ID`
- **Value**: Die Team ID aus Schritt 3 (z.B. `A1B2C3D4E5`)
- Klicke auf **Add secret**

---

## Schritt 5: Überprüfung

### Alle benötigten Secrets:

| Secret Name | Beschreibung | Beispiel |
|-------------|--------------|----------|
| `APPLE_CERTIFICATE_BASE64` | Base64-kodiertes .p12 Zertifikat | `MIIKpAIBAzCCCm4GCS...` |
| `APPLE_CERTIFICATE_PASSWORD` | Passwort für .p12 Datei | `IhrStarkesPasswort123!` |
| `APPLE_ID` | Apple ID E-Mail | `dev@schnaq.com` |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-Specific Password | `abcd-efgh-ijkl-mnop` |
| `APPLE_TEAM_ID` | Apple Developer Team ID | `A1B2C3D4E5` |

---

## Schritt 6: CI-Pipeline testen

Nachdem alle Secrets eingerichtet sind:

1. Pushe einen Commit zum `main` Branch
2. Gehe zu **Actions** Tab in GitHub
3. Beobachte den Workflow **"Build and Sign macOS App"**
4. Nach erfolgreichem Durchlauf findest du die signierte und notarisierte `.app` unter **Artifacts**

---

## Troubleshooting

### Problem: "No identity found"
- **Lösung**: Überprüfe, ob das Base64-Zertifikat korrekt konvertiert wurde
- Teste lokal: `echo "$APPLE_CERTIFICATE_BASE64" | base64 --decode > test.p12`

### Problem: "Notarization failed"
- **Lösung**:
  - Überprüfe Apple ID und App-Specific Password
  - Stelle sicher, dass 2FA für den Account aktiviert ist
  - Prüfe, ob die Team ID korrekt ist

### Problem: "Invalid signature"
- **Lösung**:
  - Stelle sicher, dass das Zertifikat vom Typ "Developer ID Application" ist
  - Überprüfe, ob das Zertifikat noch gültig ist (max. 5 Jahre)

### Problem: "codesign failed"
- **Lösung**: Überprüfe das Zertifikatspasswort

---

## Sicherheitshinweise

- **Niemals** die Secrets in Git committen
- Rotiere das App-Specific Password regelmäßig
- Das Developer ID Zertifikat ist 5 Jahre gültig - setze eine Erinnerung für die Erneuerung
- Bewahre eine Backup-Kopie des .p12 Zertifikats sicher auf (z.B. im Team-Passwort-Manager)

---

## Nützliche Links

- Apple Developer Portal: https://developer.apple.com
- Zertifikate verwalten: https://developer.apple.com/account/resources/certificates
- Notarization Guide: https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution
- App-Specific Passwords: https://appleid.apple.com

---

## Workflow-Details

Die CI-Pipeline führt folgende Schritte aus:

1. ✅ Code auschecken
2. ✅ Xcode einrichten
3. ✅ Zertifikat in temporären Keychain importieren
4. ✅ App mit Swift bauen (`build-app.sh`)
5. ✅ App mit Developer ID signieren (Hardened Runtime + Timestamp)
6. ✅ App für Notarisierung vorbereiten (ZIP erstellen)
7. ✅ App bei Apple zur Notarisierung einreichen
8. ✅ Auf Notarisierung warten (max. 30 Minuten)
9. ✅ Notarisierungs-Ticket an App heften (stapling)
10. ✅ Signierte und notarisierte App als Artefakt hochladen
11. ✅ Temporären Keychain aufräumen

Die finale `.app` kann direkt heruntergeladen und ohne Sicherheitswarnungen auf jedem Mac ausgeführt werden!
