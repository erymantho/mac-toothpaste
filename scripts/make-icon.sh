#!/usr/bin/env bash
# Builds Resources/Toothpaste.icns from the emoji in make-icon.swift.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
ICONSET="$WORK/Toothpaste.iconset"
mkdir -p "$ICONSET"

swift "$ROOT/scripts/make-icon.swift" "$WORK"

cp "$WORK/16.png"   "$ICONSET/icon_16x16.png"
cp "$WORK/32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$WORK/32.png"   "$ICONSET/icon_32x32.png"
cp "$WORK/64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$WORK/128.png"  "$ICONSET/icon_128x128.png"
cp "$WORK/256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$WORK/256.png"  "$ICONSET/icon_256x256.png"
cp "$WORK/512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$WORK/512.png"  "$ICONSET/icon_512x512.png"
cp "$WORK/1024.png" "$ICONSET/icon_512x512@2x.png"

mkdir -p "$ROOT/Resources"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/Toothpaste.icns"
rm -rf "$WORK"
echo "built: Resources/Toothpaste.icns"
