#!/bin/bash
# Full release build: app + icon + styled, signed DMG.
set -euo pipefail
cd "$(dirname "$0")"
IDENTITY="Apple Development: isaevdimka@gmail.com (XWGZQVM7YX)"

echo "== compiling =="
mkdir -p build
xcrun swiftc -O -o build/MicMute src/main.swift
xcrun swiftc -O -o build/makeicon makeicon.swift
xcrun swiftc -O -o build/makebg makebg.swift

echo "== icon =="
./build/makeicon AppIcon.iconset
iconutil -c icns AppIcon.iconset
mkdir -p MicMute.app/Contents/Resources
cp AppIcon.icns MicMute.app/Contents/Resources/
cp src/Info.plist MicMute.app/Contents/Info.plist
cp build/MicMute MicMute.app/Contents/MacOS/MicMute
cp -R ./*.lproj MicMute.app/Contents/Resources/
codesign --force --sign "$IDENTITY" --timestamp MicMute.app || codesign --force --sign - MicMute.app

echo "== DMG =="
rm -rf dmg-staging MicMute-1.0.dmg MicMute-rw.dmg
mkdir -p dmg-staging/.background
cp -R MicMute.app dmg-staging/
ln -s /Applications dmg-staging/Applications
cp AppIcon.icns dmg-staging/.VolumeIcon.icns
./build/makebg dmg-staging/.background/background.png

hdiutil create -volname MicMute -srcfolder dmg-staging -ov -format UDRW MicMute-rw.dmg >/dev/null
MNT=$(hdiutil attach -nobrowse -readwrite MicMute-rw.dmg | tail -1 | awk '{print $NF}')
VOL=$(basename "$MNT")
osascript style-dmg.applescript "$VOL" || true
hdiutil detach "$MNT" >/dev/null
hdiutil convert MicMute-rw.dmg -format UDZO -imagekey zlib-level=9 -o MicMute-1.0.dmg >/dev/null
rm MicMute-rw.dmg
codesign --sign "$IDENTITY" --timestamp MicMute-1.0.dmg || codesign --sign - MicMute-1.0.dmg
echo "Done: $PWD/MicMute-1.0.dmg"
