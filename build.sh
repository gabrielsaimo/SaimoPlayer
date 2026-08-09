#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
APP="build/Saimo TV.app"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

./make_icon.sh >/dev/null
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

swiftc \
  -swift-version 5 \
  -target arm64-apple-macos15.0 \
  -O \
  -framework AVKit \
  -framework MediaPlayer \
  -framework AVFoundation \
  -framework SwiftUI \
  -framework AppKit \
  -o "$APP/Contents/MacOS/SaimoTV" \
  Sources/*.swift

codesign --force --sign - --identifier dev.saimo.player "$APP" >/dev/null 2>&1 || true

echo "built: $APP"
