#!/bin/bash
# Baut BudsBar.app und packt sie in eine .dmg.
#
#   ./scripts/build-dmg.sh                 # lokal bauen (ad-hoc signiert)
#   UNIVERSAL=1 ./scripts/build-dmg.sh     # Apple Silicon + Intel (braucht Xcode)
#
# Optional für die Weitergabe ohne Gatekeeper-Warnung:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
#   NOTARY_PROFILE="budsbar"   # vorher: xcrun notarytool store-credentials budsbar ...
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
OUT="build"
APP="$OUT/BudsBar.app"

echo "==> Kompilieren"
if [ "${UNIVERSAL:-0}" = "1" ]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN=".build/apple/Products/Release/BudsBar"
else
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/BudsBar"
fi

echo "==> Selbsttest"
"$BIN" --selftest

echo "==> App-Bundle"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BudsBar"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

echo "==> Signieren"
if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --entitlements Resources/BudsBar.entitlements --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"

echo "==> DMG"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Programme"
DMG="$OUT/BudsBar-$VERSION.dmg"
hdiutil create -volname "BudsBar" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Notarisieren"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "Fertig: $DMG"
