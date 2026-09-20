#!/bin/bash
# Builds SmartCopyPaste.app into ./build/.
# Ad-hoc signed with a stable bundle identifier so TCC (Accessibility)
# attributes permission to com.local.smartcopypaste across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/SmartCopyPaste.app"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/$CONFIG/SmartCopyPaste" "$APP/Contents/MacOS/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.local.smartcopypaste</string>
    <key>CFBundleName</key><string>SmartCopyPaste</string>
    <key>CFBundleExecutable</key><string>SmartCopyPaste</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier com.local.smartcopypaste "$APP" 2>/dev/null || true

echo "Built $APP"
echo "Run it:  open $APP"
echo "Note:    after rebuilding, if the app loses Accessibility permission run"
echo "         tccutil reset Accessibility com.local.smartcopypaste && open $APP"
