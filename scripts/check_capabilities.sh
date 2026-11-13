#!/usr/bin/env bash
# Swift Playgrounds 版（.swiftpm/Package.swift）と正式アプリ版（project.yml）の権限設定が揃っているか確認する。
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
check() {
  local plistKey="$1" capability="$2"
  if ! grep -q "$plistKey" project.yml; then echo "::error::project.yml に $plistKey がありません"; status=1; fi
  if ! grep -q "\.$capability(" HUDNavigator.swiftpm/Package.swift; then echo "::error::Package.swift に .$capability がありません"; status=1; fi
}
check NSCameraUsageDescription camera
check NSLocationWhenInUseUsageDescription locationWhenInUse
check NSMicrophoneUsageDescription microphone
check NSSpeechRecognitionUsageDescription speechRecognition
check NSMotionUsageDescription motion
check NSBluetoothAlwaysUsageDescription bluetoothAlways
check NSCalendarsFullAccessUsageDescription calendars
# URL スキーム（ウィジェット・ショートカットから開く）は正式アプリのみ
grep -q "hudnavigator" project.yml || { echo "::error::project.yml に URL スキームがありません"; status=1; }
# Core は Foundation 以外を import しない（Linux でテストするため）
if grep -rnE '^import (SwiftUI|UIKit|AVFoundation|CoreLocation|MapKit|Vision|CoreML|CoreMotion|Speech)' HUDNavigator.swiftpm/Core; then
  echo "::error::Core/ で Apple 専用フレームワークを import しています"; status=1
fi
# App から HUDCore を import しない（Playgrounds では同じモジュールのため）
if grep -rn '^import HUDCore' HUDNavigator.swiftpm/App; then
  echo "::error::App/ で import HUDCore は使えません"; status=1
fi
[[ $status -eq 0 ]] && echo "権限設定・import ルール OK"
exit $status
