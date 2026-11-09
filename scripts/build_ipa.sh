#!/usr/bin/env bash
# 未署名の IPA を作る（AltStore が署名してインストールする）。
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-dist}"
mkdir -p "$OUT" build/logs
# AltStore が更新を見つけられるよう、ビルドごとにバージョンを上げる（0.2.<ビルド番号>）
VERSION_ARGS=()
if [[ -n "${GITHUB_RUN_NUMBER:-}" ]]; then
  VERSION_ARGS=(MARKETING_VERSION="0.2.${GITHUB_RUN_NUMBER}" CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER}")
fi
set -o pipefail
xcodebuild \
  -project HUDNavigator.xcodeproj \
  -scheme HUDNavigator \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DeviceData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS="" \
  "${VERSION_ARGS[@]}" \
  -quiet \
  build 2>&1 | tee build/logs/device.log

APP="build/DeviceData/Build/Products/Release-iphoneos/HUDNavigator.app"
test -d "$APP"
rm -f "$OUT/HUDNavigator.ipa" "$OUT/HUDNavigator-widgets.ipa"

# ウィジェット付き（AltStore の無料アカウントでは App ID を 2 つ使う）
if [[ -d "$APP/PlugIns/HUDNavigatorWidgets.appex" ]]; then
  rm -rf build/ipa-widgets
  mkdir -p build/ipa-widgets/Payload
  cp -R "$APP" build/ipa-widgets/Payload/
  (cd build/ipa-widgets && zip -qry "../../$OUT/HUDNavigator-widgets.ipa" Payload)
  /usr/libexec/PlistBuddy -c "Print NSExtension:NSExtensionPointIdentifier" "$APP/PlugIns/HUDNavigatorWidgets.appex/Info.plist"
else
  echo "::warning::ウィジェット拡張が見つかりません（ウィジェット付き IPA は作りません）"
fi

# 標準（拡張なし：App ID を 1 つしか使わない）
rm -rf build/ipa
mkdir -p build/ipa/Payload
cp -R "$APP" build/ipa/Payload/
rm -rf build/ipa/Payload/HUDNavigator.app/PlugIns build/ipa/Payload/HUDNavigator.app/Extensions
(cd build/ipa && zip -qry "../../$OUT/HUDNavigator.ipa" Payload)
ls -lh "$OUT"/*.ipa
/usr/libexec/PlistBuddy -c "Print CFBundleURLTypes:0:CFBundleURLSchemes:0" "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Info.plist"
