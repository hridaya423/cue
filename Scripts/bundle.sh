#!/bin/bash
# Builds Cue.app into ./build/.
# Ad-hoc signed with a stable bundle identifier so TCC (Accessibility)
# attributes permission to com.local.cue across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Cue.app"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Cue" "$APP/Contents/MacOS/"

# SPM resource bundles (e.g. the Redact tokenizer vectors) — Bundle.module
# resolves them from Contents/Resources inside a .app.
find ".build/$CONFIG" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \;

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.local.cue</string>
    <key>CFBundleName</key><string>Cue</string>
    <key>CFBundleExecutable</key><string>Cue</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier com.local.cue "$APP" 2>/dev/null || true

echo "Built $APP"
echo "Run it:  open $APP"
echo "Note:    after rebuilding, if the app loses Accessibility permission run"
echo "         tccutil reset Accessibility com.local.cue && open $APP"
