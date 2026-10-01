#!/bin/bash
# Builds Cue.app into ./build/.
# Signed with a real identity when available: TCC keys ad-hoc apps by
# cdhash, which changes every rebuild — granted Accessibility toggles
# silently go stale. A cert signature keeps com.local.cue's requirement
# stable, so the grant persists across rebuilds.
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
# -H: .build/$CONFIG is a symlink to .build/<triple>/$CONFIG — without it
# find never descends and the resource bundle silently doesn't ship.
find -H ".build/$CONFIG" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \;

# The Laya server shim — the managed-model installer runs this inside the
# model's venv to speak /v1/systemone.
cp Scripts/laya_server.py "$APP/Contents/Resources/"

# App icon (generated: `swift Scripts/make_icon.swift build/Cue.iconset`
# then `iconutil -c icns` — regenerate if the mark changes).
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.local.cue</string>
    <key>CFBundleName</key><string>Cue</string>
    <key>CFBundleExecutable</key><string>Cue</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Mac Developer/{print $2; exit}')"
if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" --identifier com.local.cue "$APP"
else
    codesign --force --sign - --identifier com.local.cue "$APP" 2>/dev/null || true
fi

echo "Built $APP"
echo "Run it:  open $APP"
echo "Note:    cert-signed builds keep the Accessibility grant across rebuilds;"
echo "         if it was ad-hoc signed and stuck, reset once: tccutil reset Accessibility com.local.cue"
