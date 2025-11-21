# Watson GUI

Minimale macOS Menu-Bar App für [Watson](https://github.com/jazzband/Watson) Time Tracker.

## Features

- Zeigt aktuellen Tracking-Status in der Menu-Bar (Projekt + Dauer)
- "Stop Tracking" per Klick
- Tagesstatistik anzeigen
- Push-Erinnerung nach 5 Minuten ohne Tracking (wenn Mac aktiv)

## Voraussetzungen

- macOS 13+
- Watson CLI installiert (`pip install td-watson` oder `brew install watson`)

## Build

```bash
cd WatsonGUI
swift build -c release
```

Das Binary liegt dann unter `.build/release/WatsonGUI`.

## Installation

1. Binary nach `/Applications` oder `~/Applications` kopieren
2. Bei Bedarf signieren: `codesign --sign "Developer ID" WatsonGUI`
3. Optional: Zu Login Items hinzufügen für Autostart

## Xcode-Projekt erstellen (für Signierung)

```bash
cd WatsonGUI
swift package generate-xcodeproj
```

Dann in Xcode öffnen und Signing konfigurieren.
