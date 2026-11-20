#!/bin/bash
# Упаковка MicMute для Mac App Store.
#
# Что понадобится после покупки Apple Developer Program ($99/год):
#   1. App Store Connect -> Identifiers -> App ID (например com.isaevdimka.micmute, тип Mac)
#   2. Certificates -> Apple Distribution сертификат (создаётся в Xcode или developer.apple.com)
#   3. Profiles -> Mac App Store provisioning profile для этого App ID -> скачать .provisionprofile
#   4. App Store Connect -> Apps -> новое приложение (SKU, название MicMute)
#
# Затем:
#   MAS_IDENTITY="Apple Distribution: Ваше Имя (TEAMID)" \
#   MAS_PROFILE=/путь/MicMute.provisionprofile \
#   ./mas.sh
#
# Результат: mas/MicMute-mas.zip — загрузить в App Store Connect через приложение Transporter.
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${MAS_IDENTITY:?Задайте MAS_IDENTITY='Apple Distribution: Имя (TEAMID)'}"
PROFILE="${MAS_PROFILE:?Задайте MAS_PROFILE=путь к .provisionprofile}"
BUNDLE_ID="${MAS_BUNDLE_ID:-com.isaevdimka.micmute}"
VERSION="${MAS_VERSION:-1.1}"

echo "== сборка (Carbon-режим для песочницы) =="
mkdir -p build
xcrun swiftc -O -o build/MicMute src/main.swift

echo "== бандл =="
rm -rf mas-build
mkdir -p "mas-build/MicMute.app/Contents/MacOS" "mas-build/MicMute.app/Contents/Resources"
cp src/Info.plist "mas-build/MicMute.app/Contents/Info.plist"
cp build/MicMute "mas-build/MicMute.app/Contents/MacOS/MicMute"
if [ -f AppIcon.icns ]; then
  cp AppIcon.icns "mas-build/MicMute.app/Contents/Resources/"
else
  xcrun swiftc -O -o build/makeicon makeicon.swift
  ./build/makeicon AppIcon.iconset
  iconutil -c icns AppIcon.iconset
  cp AppIcon.icns "mas-build/MicMute.app/Contents/Resources/"
fi

# Bundle ID, версия и принудительный Carbon-режим для MAS
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "mas-build/MicMute.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "mas-build/MicMute.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :MicMuteForceCarbon true" "mas-build/MicMute.app/Contents/Info.plist"
cp -R ./*.lproj "mas-build/MicMute.app/Contents/Resources/"

echo "== подпись (sandbox + hardened runtime) =="
cp "$PROFILE" "mas-build/MicMute.app/Contents/embedded.provisionprofile"
codesign --force --sign "$IDENTITY" --timestamp \
  --entitlements MicMute.entitlements --options runtime \
  "mas-build/MicMute.app"
codesign --verify --strict --verbose=2 "mas-build/MicMute.app"

echo "== упаковка =="
ditto -c -k --keepParent "mas-build/MicMute.app" "mas-build/MicMute-mas.zip"
echo "Готово: $PWD/mas-build/MicMute-mas.zip"
echo "Загрузите через Transporter, затем в App Store Connect отправьте на review."
