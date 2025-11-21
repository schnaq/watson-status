# Watson Status

Minimale macOS Menu-Bar App für [Watson](https://github.com/jazzband/Watson) Time Tracker.

## Features

- Zeigt aktuellen Tracking-Status in der Menu-Bar (Projekt + Dauer)
- "Stop Tracking" per Klick
- Tagesstatistik anzeigen
- Erinnerung nach 5 Minuten ohne Tracking (wenn Mac aktiv)

## Voraussetzungen

- macOS 13+
- Watson CLI installiert (`pip install td-watson` oder `brew install watson`)

## Build

```bash
cd WatsonStatus
chmod +x build-app.sh
./build-app.sh
```

Erstellt `WatsonStatus.app` (Bundle ID: `com.schnaq.WatsonStatus`).

## Installation

```bash
cp -r WatsonStatus.app /Applications/
```

Optional zu Login Items hinzufügen für Autostart.

## CI/CD - Automatische Builds

Bei jedem Push zum `main` Branch wird automatisch eine signierte und notarisierte `.app` erstellt und als GitHub Actions Artefakt gespeichert.

### Setup für Code Signing

Die vollständige Anleitung zur Einrichtung der Apple Code Signing Secrets findest du in: **[CODESIGNING_SETUP.md](CODESIGNING_SETUP.md)**

### Download der signierten App

1. Gehe zu [Actions](../../actions)
2. Wähle den neuesten erfolgreichen Workflow-Run
3. Lade das Artefakt `WatsonStatus-*.zip` herunter
4. Entpacke und verschiebe `WatsonStatus.app` nach `/Applications/`

Die App ist vollständig signiert und notarisiert und läuft ohne Sicherheitswarnungen.

## Manuelle Signierung (optional)

Für lokale Builds:

```bash
codesign --force --deep --sign "Developer ID Application: DEIN NAME" WatsonStatus.app
```
