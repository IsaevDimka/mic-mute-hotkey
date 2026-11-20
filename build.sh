#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
IDENTITY="Apple Development: isaevdimka@gmail.com (XWGZQVM7YX)"
mkdir -p build
xcrun swiftc -O -o build/MicMute src/main.swift
cp src/Info.plist MicMute.app/Contents/Info.plist
cp build/MicMute MicMute.app/Contents/MacOS/MicMute
[ -f AppIcon.icns ] && cp AppIcon.icns MicMute.app/Contents/Resources/ || true
codesign --force --sign "$IDENTITY" --timestamp MicMute.app || codesign --force --sign - MicMute.app
rm -rf /Applications/MicMute.app
cp -R MicMute.app /Applications/
rm -rf /Applications/MicMute.app/Contents/Resources/*.lproj
cp -R ./*.lproj /Applications/MicMute.app/Contents/Resources/
pkill -x MicMute 2>/dev/null || true
sleep 1
launchctl bootout "gui/$(id -u)/local.micmute" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.micmute.plist" 2>/dev/null || true
echo "Собрано и развёрнуто в /Applications (агент перезапущен)"
