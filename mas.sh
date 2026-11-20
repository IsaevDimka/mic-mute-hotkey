#!/bin/bash
# Package MicMute for the Mac App Store.
#
# After enrolling in the Apple Developer Program ($99/year):
#   1. App Store Connect -> Identifiers -> App ID (e.g. com.isaevdimka.micmute, Mac)
#   2. Certificates -> create an Apple Distribution certificate
#      (via Xcode Preferences -> Accounts, or developer.apple.com)
#   3. Profiles -> Mac App Store provisioning profile for that App ID -> download .provisionprofile
#   4. App Store Connect -> Apps -> add a new app (SKU, name: MicMute)
#
# Then:
#   MAS_IDENTITY="Apple Distribution: Your Name (TEAMID)" \
#   MAS_PROFILE=/path/MicMute.provisionprofile \
#   ./mas.sh
#
# Output: mas-build/MicMute-mas.zip — upload to App Store Connect with Transporter.
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${MAS_IDENTITY:?Set MAS_IDENTITY='Apple Distribution: Name (TEAMID)'}"
PROFILE="${MAS_PROFILE:?Set MAS_PROFILE=path to .provisionprofile}"
BUNDLE_ID="${MAS_BUNDLE_ID:-com.isaevdimka.micmute}"
VERSION="${MAS_VERSION:-1.1}"

echo "== build (Carbon mode for sandbox) =="
mkdir -p build
xcrun swiftc -O -o build/MicMute src/main.swift

echo "== bundle =="
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

# Bundle ID, version, forced Carbon mode for MAS
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "mas-build/MicMute.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "mas-build/MicMute.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :MicMuteForceCarbon true" "mas-build/MicMute.app/Contents/Info.plist"
# Default hotkey ⌥M (code 46, optionKey 2048) so it works out of the box
/usr/libexec/PlistBuddy -c "Add :MicMuteDefaultKeyCode integer 46" "mas-build/MicMute.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :MicMuteDefaultModifiers integer 2048" "mas-build/MicMute.app/Contents/Info.plist"
cp -R ./*.lproj "mas-build/MicMute.app/Contents/Resources/"

echo "== signing (sandbox + hardened runtime) =="
cp "$PROFILE" "mas-build/MicMute.app/Contents/embedded.provisionprofile"
codesign --force --sign "$IDENTITY" --timestamp \
  --entitlements MicMute.entitlements --options runtime \
  "mas-build/MicMute.app"
codesign --verify --strict --verbose=2 "mas-build/MicMute.app"

echo "== packaging =="
ditto -c -k --keepParent "mas-build/MicMute.app" "mas-build/MicMute-mas.zip"
echo "Done: $PWD/mas-build/MicMute-mas.zip"
echo "Upload with Transporter, then submit for review in App Store Connect."
