#!/usr/bin/env bash
# Release のノート（実機チェックリスト付き）を作る。
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-dist}"
SHA="${GITHUB_SHA:-$(git rev-parse HEAD)}"
RUN="${GITHUB_RUN_NUMBER:-local}"
{
  echo "## HUD Navigator ビルド #${RUN}"
  echo
  echo "コミット: \`${SHA:0:7}\`  日時: $(date -u '+%Y-%m-%d %H:%M UTC')"
  echo
  echo "### ファイル"
  echo "- **HUDNavigator.ipa** … AltStore でインストールする正式アプリ（iPad / iPhone 15）。まずはこちら"
  echo "- **HUDNavigator-widgets.ipa** … ホーム画面・ロック画面のウィジェットとコントロールセンターのボタン付き（AltStore の無料アカウントでは App ID を 2 つ使います。7日で10個まで）"
  echo "- **HUDNavigator.swiftpm.zip** … iPad の Swift Playgrounds で開く版（回数無制限で試せます）"
  echo
  echo "### インストール（AltStore）"
  echo "1. この .ipa を iPad / iPhone の Safari でダウンロード（ファイルに保存）"
  echo "2. AltStore → マイApp → ＋ → HUDNavigator.ipa を選ぶ"
  echo "3. 7日ごとに AltStore で更新（署名の期限）"
  echo
  echo "### 実機チェック"
  echo "アプリの 設定 → 詳細・診断 → 実機テストモード にチェックリストがあります。"
  echo "結果を「書き出し」して GitHub の Issue に添付してください。"
  echo "手順書: docs/user_guide.md / docs/device_test_checklist.md"
  echo
  echo "### 最近の変更"
  git log -n 15 --pretty='- %s' || true
} > "$OUT/RELEASE_NOTES.md"
cat "$OUT/RELEASE_NOTES.md"
