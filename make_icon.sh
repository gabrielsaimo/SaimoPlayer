#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Prefers a hand-made AppIcon.png in the project root; falls back to the
# drawn one so the bundle is never left without an icon.
SRC="build/icon.png"
if [ -f AppIcon.png ]; then
  SRC="AppIcon.png"
  echo "usando AppIcon.png"
else
  mkdir -p build
  swift MakeIcon.swift "$SRC" >/dev/null
  echo "usando ícone desenhado"
fi

SET="build/AppIcon.iconset"
rm -rf "$SET"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s      "$SRC" --out "$SET/icon_${s}x${s}.png"    >/dev/null
  sips -z $((s*2)) $((s*2)) "$SRC" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o build/AppIcon.icns
rm -rf "$SET"
echo "AppIcon.icns pronto"
