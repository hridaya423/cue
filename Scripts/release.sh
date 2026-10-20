#!/bin/bash
# Builds a shippable build/Cue-<version>.dmg: Developer ID signature with the hardened runtime, notarized by
# Apple and stapled, so Gatekeeper opens it on any Mac without a warning.
#
# Needs, once per Mac:
#   1. A "Developer ID Application" certificate in the login keychain
#      (Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application).
#   2. Notary credentials saved under the profile name below:
#      xcrun notarytool store-credentials cue-notary --apple-id <you@example.com> --team-id <TEAMID>
#
# SKIP_NOTARIZE=1 stops after signing and packing (for checking the build without submitting it).
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-cue-notary}"
IDENTITY="${DEVELOPER_ID:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')}"
if [ -z "$IDENTITY" ]; then
    echo "No Developer ID Application certificate found. See the header of $0." >&2
    exit 1
fi

Scripts/bundle.sh release
APP="build/Cue.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/Cue-$VERSION.dmg"

codesign --force --options runtime --timestamp --sign "$IDENTITY" --identifier com.local.cue "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto "$APP" "$stage/Cue.app"
ln -s /Applications "$stage/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Cue" -srcfolder "$stage" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ "${SKIP_NOTARIZE:-}" = 1 ]; then
    echo "Signed, not notarized: $DMG"
    exit 0
fi

xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
echo "Ready to ship: $DMG"
