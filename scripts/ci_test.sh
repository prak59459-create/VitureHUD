#!/usr/bin/env bash
# iOS シミュレータでビルド・テストし、HUD のスナップショット画像を build/snapshots に書き出す。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/snapshots build/logs

# 使えるシミュレータ（iPhone）を1台選ぶ
DEST_ID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    for d in devices:
        if d.get("isAvailable") and d["name"].startswith("iPhone"):
            key = (runtime, d["name"])
            if best is None or key > best[0]:
                best = (key, d["udid"])
print(best[1] if best else "")
')
if [[ -z "$DEST_ID" ]]; then
  echo "::error::利用できる iPhone シミュレータがありません"
  xcrun simctl list devices available
  exit 1
fi
echo "Simulator: $DEST_ID"

export TEST_RUNNER_SNAPSHOT_DIR="$PWD/build/snapshots"
set -o pipefail
xcodebuild \
  -project HUDNavigator.xcodeproj \
  -scheme HUDNavigator \
  -destination "id=$DEST_ID" \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/TestResults.xcresult \
  -quiet \
  test 2>&1 | tee build/logs/test.log
