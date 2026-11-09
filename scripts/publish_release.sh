#!/usr/bin/env bash
# 既定ブランチへの push ごとに「latest」リリース（プレリリース）を作り直す。v* タグのときは正式リリース。
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-dist}"
if [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
  TAG="${GITHUB_REF#refs/tags/}"
  gh release create "$TAG" "$OUT"/HUDNavigator.ipa "$OUT"/HUDNavigator.swiftpm.zip \
    --title "HUD Navigator $TAG" --notes-file "$OUT/RELEASE_NOTES.md" --verify-tag
else
  gh release delete latest --yes --cleanup-tag >/dev/null 2>&1 || true
  git push --delete origin latest >/dev/null 2>&1 || true
  gh release create latest "$OUT"/HUDNavigator.ipa "$OUT"/HUDNavigator.swiftpm.zip \
    --prerelease --title "最新ビルド（#${GITHUB_RUN_NUMBER:-0}）" \
    --notes-file "$OUT/RELEASE_NOTES.md" --target "${GITHUB_SHA}"
fi
