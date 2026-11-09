#!/usr/bin/env bash
# 使う Xcode を選ぶ。XCODE_VERSION（例: 26.1）があればそれ、無ければ既定の Xcode。
set -euo pipefail
if [[ -n "${XCODE_VERSION:-}" && -d "/Applications/Xcode_${XCODE_VERSION}.app" ]]; then
  sudo xcode-select -s "/Applications/Xcode_${XCODE_VERSION}.app"
fi
xcode-select -p
xcodebuild -version
