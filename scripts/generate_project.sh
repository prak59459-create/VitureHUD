#!/usr/bin/env bash
# XcodeGen で HUDNavigator.xcodeproj を生成する（CI 用）。
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi
mkdir -p build/generated
xcodegen generate --spec project.yml
