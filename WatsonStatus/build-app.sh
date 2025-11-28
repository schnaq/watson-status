#!/bin/bash
set -e

APP_NAME="WatsonStatus"
BUNDLE_ID="com.schnaq.WatsonStatus"
VERSION="1.0.0"

# Build release
swift build -c release

# Create .app structure
rm -rf "$APP_NAME.app"
mkdir -p "$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_NAME.app/Contents/Resources"

# Copy binary
cp .build/release/$APP_NAME "$APP_NAME.app/Contents/MacOS/"

# Create Info.plist with notification usage description
cat > "$APP_NAME.app/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Watson Status</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSUserNotificationsUsageDescription</key>
    <string>WatsonStatus needs permission to send you reminders when you forget to track your time.</string>
</dict>
</plist>
EOF

# Create entitlements file for notifications
cat > "$APP_NAME.app/Contents/entitlements.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.application-identifier</key>
    <string>$BUNDLE_ID</string>
</dict>
</plist>
EOF

# Ad-hoc sign the app (required for notifications to work)
echo "Signing app with ad-hoc signature..."
codesign --sign - --force --deep --entitlements "$APP_NAME.app/Contents/entitlements.plist" "$APP_NAME.app"

# Verify signature
echo "Verifying signature..."
codesign --verify --verbose "$APP_NAME.app"

echo ""
echo "✅ Built: $APP_NAME.app"
echo ""
echo "📦 To install:"
echo "   1. First, quit any running instance of WatsonStatus"
echo "   2. Remove old version: rm -rf /Applications/$APP_NAME.app"
echo "   3. Install new version: cp -r $APP_NAME.app /Applications/"
echo "   4. Launch from Applications folder"
echo ""
echo "🔐 For distribution (optional):"
echo "   codesign --force --deep --sign \"Developer ID Application: YOUR NAME\" \\"
echo "     --entitlements $APP_NAME.app/Contents/entitlements.plist \\"
echo "     --options runtime --timestamp $APP_NAME.app"
echo ""
echo "⚠️  Important: If notifications still don't work after installation:"
echo "   - Completely quit WatsonStatus"
echo "   - Run: tccutil reset UserNotifications com.schnaq.WatsonStatus"
echo "   - Restart your Mac (recommended)"
echo "   - Launch WatsonStatus again"
echo ""
