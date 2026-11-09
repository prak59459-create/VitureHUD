#!/usr/bin/env bash
# 未署名の IPA を作る（AltStore が署名してインストールする）。
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-dist}"
mkdir -p "$OUT" build/logs
set -o pipefail
xcodebuild \
  -project HUDNavigator.xcodeproj \
  -scheme HUDNavigator \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DeviceData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS="" \
  -quiet \
  build 2>&1 | tee build/logs/device.log

APP="build/DeviceData/Build/Products/Release-iphoneos/HUDNavigator.app"
test -d "$APP"
rm -rf build/ipa
mkdir -p build/ipa/Payload
cp -R "$APP" build/ipa/Payload/
(cd build/ipa && zip -qry "../../$OUT/HUDNavigator.ipa" Payload)
ls -lh "$OUT/HUDNavigator.ipa"
/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Info.plist"
