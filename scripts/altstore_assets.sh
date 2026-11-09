#!/usr/bin/env bash
# AltStore のソース（JSON）・アイコン・スクリーンショットを dist に用意する。build_ipa.sh の後に実行。
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-dist}"
APP="build/DeviceData/Build/Products/Release-iphoneos/HUDNavigator.app"
test -f "$APP/Info.plist"
if [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
  export RELEASE_TAG="${GITHUB_REF#refs/tags/}"
else
  export RELEASE_TAG="latest"
fi

cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png "$OUT/icon.png"

# スクリーンショット（シミュレータのテストで作った HUD の画像。なければスキップ）
i=1
for name in preset-walkNav-1920x1080 theme-cyberpunk widgets-new preset-travel-1920x1080; do
  if [[ -f "build/snapshots/$name.png" ]]; then
    cp "build/snapshots/$name.png" "$OUT/screenshot-$i.png"
    i=$((i + 1))
  fi
done

python3 scripts/altstore_source.py "$APP/Info.plist" "$OUT/HUDNavigator.ipa" "$OUT/altstore-source.json"
if [[ -f "$OUT/HUDNavigator-widgets.ipa" ]]; then
  python3 scripts/altstore_source.py "$APP/Info.plist" "$OUT/HUDNavigator-widgets.ipa" "$OUT/altstore-source-widgets.json" --widgets
fi
python3 -c "import json,sys; [json.load(open(p)) for p in sys.argv[1:]]; print('JSON OK')" "$OUT"/altstore-source*.json
ls -lh "$OUT"
