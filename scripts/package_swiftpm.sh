#!/usr/bin/env bash
# Swift Playgrounds（iPad）で開ける zip を作る。
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-dist}"
mkdir -p "$OUT"
rm -f "$OUT/HUDNavigator.swiftpm.zip"
if command -v ditto >/dev/null 2>&1; then
  ditto -c -k --keepParent HUDNavigator.swiftpm "$OUT/HUDNavigator.swiftpm.zip"
else
  zip -qry "$OUT/HUDNavigator.swiftpm.zip" HUDNavigator.swiftpm -x '*/.build/*'
fi
ls -lh "$OUT/HUDNavigator.swiftpm.zip"
