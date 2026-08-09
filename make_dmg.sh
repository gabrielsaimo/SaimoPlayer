#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Saimo TV.app"
STAGE="build/dmg"
DMG="build/SaimoTV.dmg"

./build.sh
python3 bundle_ffmpeg.py "$APP"
codesign --force --deep --sign - --identifier dev.saimo.player "$APP" >/dev/null 2>&1 || true

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Saimo TV" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "DMG: $DMG ($(du -h "$DMG" | cut -f1))"
