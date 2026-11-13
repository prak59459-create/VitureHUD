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
rm -f "$OUT"/screenshot-*
for name in ui-home.jpg ui-work-focus.jpg ui-hud-editor.jpg ui-work-browser-remote.jpg ui-assistant-chat.jpg preset-desk-1920x1080.png preset-walkNav-1920x1080.png; do
  if [[ -f "build/snapshots/$name" ]]; then
    cp "build/snapshots/$name" "$OUT/screenshot-$i.${name##*.}"
    i=$((i + 1))
  fi
done

python3 scripts/altstore_source.py "$APP/Info.plist" "$OUT/HUDNavigator.ipa" "$OUT/altstore-source.json"
if [[ -f "$OUT/HUDNavigator-widgets.ipa" ]]; then
  python3 scripts/altstore_source.py "$APP/Info.plist" "$OUT/HUDNavigator-widgets.ipa" "$OUT/altstore-source-widgets.json" --widgets
fi
python3 -c "import json,sys; [json.load(open(p)) for p in sys.argv[1:]]; print('JSON OK')" "$OUT"/altstore-source*.json
ls -lh "$OUT"
