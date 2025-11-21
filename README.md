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

## Signierung

```bash
codesign --force --deep --sign "Developer ID Application: DEIN NAME" WatsonStatus.app
```
