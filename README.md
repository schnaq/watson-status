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

### Option 1: Download Pre-Built App (Recommended)

A signed and notarized version of WatsonStatus is automatically built on every push to `main` and available as a GitHub Actions artifact:

1. Go to [Actions](../../actions)
2. Select the latest successful workflow run
3. Download the `WatsonStatus-*.zip` artifact
4. Extract and move `WatsonStatus.app` to `/Applications/`

The app is fully signed and notarized - no security warnings!

### Option 2: Build from Source

**Important:** The build script automatically signs the app with an ad-hoc signature, which is required for notifications to work.

```bash
cd WatsonStatus
chmod +x build-app.sh
./build-app.sh

# Install to /Applications (required for notifications)
cp -r WatsonStatus.app /Applications/

# Launch and allow notifications when prompted
open /Applications/WatsonStatus.app
```

**Note:** If you've run an older version before, you may need to reset macOS notification permissions. See [Troubleshooting → Notifications](#notifications-not-showing).

### Option 3: Add to Login Items

To launch automatically on startup:
1. Open **System Settings** → **General** → **Login Items**
2. Add `WatsonStatus.app` to the list

## CI/CD - Automated Builds

Every push to the `main` branch automatically triggers a GitHub Actions workflow that:

- ✅ Builds the app with Swift
- ✅ Signs the app with Apple Developer ID (Hardened Runtime + Timestamp)
- ✅ Notarizes the app with Apple (required for macOS Big Sur+)
- ✅ Uploads the signed and notarized `.app` as a GitHub Actions artifact
- ✅ Retains artifacts for 90 days

### Setting Up Code Signing

For detailed instructions on setting up the required Apple Developer secrets, see **[CODESIGNING_SETUP.md](CODESIGNING_SETUP.md)**.

You'll need to configure these 5 secrets in GitHub Actions:
- `APPLE_CERTIFICATE_BASE64` - Base64-encoded .p12 certificate
- `APPLE_CERTIFICATE_PASSWORD` - Password for the .p12 file
- `APPLE_ID` - Apple Developer Account email
- `APPLE_APP_SPECIFIC_PASSWORD` - App-specific password from appleid.apple.com
- `APPLE_TEAM_ID` - 10-character Team ID from Apple Developer Portal

See the [setup guide](CODESIGNING_SETUP.md) for step-by-step instructions on obtaining each secret.

## Usage

### Menu Bar Interface

- **Click the menu bar icon** to open the menu
- **Stop Tracking** - Stops the current time tracking session (shortcut: `⌘S`)
- **Start Project** - Submenu with your 10 most recent projects
- **Today's Stats** - Shows detailed daily time report (shortcut: `⌘T`)
- **Notification Settings…** - Check notification permission status and enable if needed
- **Quit** - Exit the application (shortcut: `⌘Q`)

### Configuration

You can modify the reminder interval by editing `main.swift`:

```swift
let reminderIntervalMinutes: Double = 5  // Change to your preference
```

## Code Signing (Manual)

For manual code signing of local builds to avoid Gatekeeper warnings:

```bash
codesign --force --deep --sign "Developer ID Application: YOUR NAME" WatsonStatus.app
```

For automated CI/CD signing, see the [CI/CD section](#cicd---automated-builds) above.

## Architecture

- **Language**: Swift
- **Minimum Swift Version**: 5.9
- **Frameworks**: AppKit, UserNotifications
- **Build System**: Swift Package Manager
- **Bundle ID**: `com.schnaq.WatsonStatus`
- **Code Signing**: Ad-hoc signature for local builds, Developer ID for distribution
- **Entitlements**: Notifications enabled (no sandbox for Watson CLI access)

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
├── .github/
│   └── workflows/
│       └── build-macos-app.yml    # CI/CD pipeline
├── WatsonStatus/
│   ├── Package.swift              # Swift package manifest
│   ├── Sources/
│   │   └── main.swift             # Main application code
│   └── build-app.sh               # Build script
├── CODESIGNING_SETUP.md           # Code signing guide
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

**WatsonStatus needs notification permissions to send reminders when you're not tracking time.**

#### Checking Permission Status
1. Click the WatsonStatus menu bar icon
2. Select **Notification Settings…**
3. The app will show whether notifications are enabled or disabled

#### Enabling Notifications
If notifications are disabled:
1. Click **Notification Settings…** in the menu
2. Click **Open Settings** to go directly to System Settings
3. Find **WatsonStatus** in the list
4. Toggle on **Allow Notifications**

Alternatively, manually enable in:
**System Settings** → **Notifications** → **WatsonStatus**

#### First Launch Behavior
- On first launch, macOS should prompt you to allow notifications
- If you accidentally denied permission, use the menu to check and enable it
- The app will display helpful messages in the console/logs about notification status

#### App doesn't appear in Notification Settings

If WatsonStatus doesn't appear in **System Settings → Notifications**, this means macOS hasn't recognized the app properly. This can happen when:

1. **The app wasn't properly signed** - The build script now automatically ad-hoc signs the app
2. **macOS cached an old version** - Follow the reset steps below
3. **The app wasn't launched from /Applications** - Always install to /Applications folder

**Solution - Complete Reset:**

```bash
# 1. Quit WatsonStatus completely
killall WatsonStatus 2>/dev/null

# 2. Remove old installation
rm -rf /Applications/WatsonStatus.app

# 3. Reset macOS notification permission cache
tccutil reset UserNotifications com.schnaq.WatsonStatus

# 4. Rebuild and reinstall
cd WatsonStatus
./build-app.sh
cp -r WatsonStatus.app /Applications/

# 5. Restart your Mac (IMPORTANT - macOS caches notification settings)
sudo shutdown -r now
```

**After restart:**
1. Launch WatsonStatus from `/Applications/`
2. macOS should now prompt for notification permission
3. Click "Allow" when prompted
4. Verify in **System Settings → Notifications** that WatsonStatus appears

**Still not working?**

Check the Console app for errors:
```bash
# Open Console.app and filter for "WatsonStatus"
open -a Console
```

Look for errors related to:
- `UserNotifications` framework
- TCC (Transparency, Consent, and Control) database
- Code signing issues

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
