# Watson Status

A minimal macOS menu bar application for the [Watson](https://github.com/jazzband/Watson) time tracker.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Live tracking status** - Displays the current project and elapsed time in the menu bar
- **Quick stop tracking** - Stop your current time tracking session with one click
- **Recent projects** - Quick-start menu with your 10 most recent projects and tags
- **Daily statistics** - View today's time tracking report in a convenient modal
- **Smart reminders** - Push notifications after 5 minutes of inactivity (only when Mac is active)
- **Auto-stop on sleep** - Automatically stops tracking when your Mac goes to sleep
- **Minimal UI** - Clean menu bar integration that doesn't get in your way

## Screenshots

- Active tracking: `⏱ project-name (2h15m)` (green)
- Idle state: `⏱ —` (orange)

## Prerequisites

- macOS 13.0 or later
- Watson CLI installed via:
  - Homebrew: `brew install watson`
  - pip: `pip install td-watson`

## Installation

### Option 1: Build from source

```bash
cd WatsonStatus
chmod +x build-app.sh
./build-app.sh
cp -r WatsonStatus.app /Applications/
```

### Option 2: Add to Login Items

To launch automatically on startup:
1. Open **System Settings** → **General** → **Login Items**
2. Add `WatsonStatus.app` to the list

## Usage

### Menu Bar Interface

- **Click the menu bar icon** to open the menu
- **Stop Tracking** - Stops the current time tracking session (shortcut: `⌘S`)
- **Start Project** - Submenu with your 10 most recent projects
- **Today's Stats** - Shows detailed daily time report (shortcut: `⌘T`)
- **Quit** - Exit the application (shortcut: `⌘Q`)

### Configuration

You can modify the reminder interval by editing `main.swift`:

```swift
let reminderIntervalMinutes: Double = 5  // Change to your preference
```

## Code Signing (Optional)

For distribution or to avoid Gatekeeper warnings:

```bash
codesign --force --deep --sign "Developer ID Application: YOUR NAME" WatsonStatus.app
```

## Architecture

- **Language**: Swift
- **Minimum Swift Version**: 5.9
- **Frameworks**: AppKit, UserNotifications
- **Build System**: Swift Package Manager
- **Bundle ID**: `com.schnaq.WatsonStatus`

## How It Works

1. **Status Updates**: Polls Watson status every 5 seconds to update the menu bar
2. **Watson Integration**: Executes Watson CLI commands via shell (`watson status`, `watson stop`, etc.)
3. **Idle Detection**: Checks every 30 seconds if tracking has been idle for 5+ minutes
4. **Activity Detection**: Only sends reminders if mouse activity detected in last 2 minutes
5. **Recent Projects**: Parses `watson log --json` to build quick-start menu

## Development

### Project Structure

```
watson-status/
├── WatsonStatus/
│   ├── Package.swift          # Swift package manifest
│   ├── Sources/
│   │   └── main.swift         # Main application code
│   └── build-app.sh           # Build script
└── README.md
```

### Building for Development

```bash
cd WatsonStatus
swift build
.build/debug/WatsonStatus
```

### Building for Release

```bash
cd WatsonStatus
swift build -c release
```

## Troubleshooting

### Watson not found
The app searches for Watson in these locations:
- `/opt/homebrew/bin/watson` (Apple Silicon Homebrew)
- `/usr/local/bin/watson` (Intel Homebrew)
- `/usr/bin/watson`
- PATH environment variable

### Notifications not showing
Grant notification permissions when prompted on first launch, or manually enable in:
**System Settings** → **Notifications** → **WatsonStatus**

### App doesn't update
Ensure Watson is properly configured and responding to CLI commands:
```bash
watson status
watson log
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

MIT License - see the code for details.

## Credits

Built for the [Watson](https://github.com/jazzband/Watson) time tracking CLI by the Jazzband community.
