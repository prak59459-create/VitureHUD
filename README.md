# HUD Navigator

VITURE XR グラス × iPad A16 / iPhone 15 向けのスマート HUD ナビゲーションアプリ（SwiftUI）。

- 黒背景（グラス上で透明）／カメラ背景の HUD
- 自由に配置できるパネル（23種のウィジェット・テンプレート文字）、テーマ7種・プリセット7種＋自作
- Apple MapKit のナビ（検索・周辺施設・ルート比較・音声案内・リルート・デモ再生）＋任意の Google Maps（乗り換え案内・評価・営業時間）
- センサー（GPS・コンパス・加速度・ジャイロ・AirPods の頭の向き・Bluetooth 心拍計・外部カメラ）と省電力制御
- 物体認識（YOLOv3 を内蔵・80 種類・黒背景でも動く）・危険検知・白線・標識の読み取り（実験機能・安全装置ではない）
- 距離の推定（LiDAR／2 つのカメラ／AI の Depth Anything V2）・近くの物の警告・3D スキャン（点群・メッシュ・PLY 書き出し）
- 頭の動き（AirPods／Bluetooth センサー／VITURE 本体 USB〔実験〕／前面カメラ）で空間固定・ジェスチャー操作・チラ見モード
- 明るさ・夜の自動減光・3D（左右分割）・AirPods での空間固定
- 日本語の音声コマンド（端末内）＋任意のクラウド AI（APIキー・同意制。AI がアプリを操作することも可能）＋状況に合わせた提案
- 天気・空気質・1時間ごとの予報（Open-Meteo）、通知設定、移動履歴・訪問した場所・利用状況、iCloud Drive フォルダでの自動同期
- ショートカット・URL 操作・ホーム画面ウィジェット・コントロールセンター（正式アプリのみ）、iPad のキーボード操作、実機テストモード

## 入手

### AltStore のソース（おすすめ・更新が自動で届く）
AltStore →「ソース（Sources）」→「＋」→ 次の URL を追加：

```
https://github.com/prak59459-create/VitureHUD/releases/download/latest/altstore-source.json
```

ウィジェット付きの版は `https://github.com/prak59459-create/VitureHUD/releases/download/latest/altstore-source-widgets.json`（どちらか一方だけ追加してください）。

### ファイルで入手

[Releases](https://github.com/prak59459-create/VitureHUD/releases) の「最新ビルド」から：

| ファイル | 使い方 |
|---------|--------|
| `HUDNavigator.swiftpm.zip` | iPad の **Swift Playgrounds** で開く（回数無制限で試せる） |
| `HUDNavigator.ipa` | **AltStore** で iPad / iPhone 15 にインストール（7日ごとに更新） |
| `HUDNavigator-widgets.ipa` | 上と同じ＋ホーム画面・ロック画面のウィジェットとコントロールセンターのボタン（App ID を2つ使う） |

使い方：[docs/user_guide.md](docs/user_guide.md)　／　実機テスト：[docs/device_test_checklist.md](docs/device_test_checklist.md)

## 開発・検証の流れ

```
このリポジトリ（ソースは HUDNavigator.swiftpm/ の1か所）
 ├─▶ Swift Playgrounds（iPad A16）… 回数無制限で試す（CI が配る .swiftpm.zip を開く）
 ├─▶ GitHub Actions … Linuxテスト → iOSビルド・シミュレータテスト・スナップショット
 └─▶ 未署名 IPA を GitHub Release に添付 ─▶ AltStore で iPhone 15 / iPad に正式インストール（週7回まで）
```

| ビルド定義 | 用途 |
|-----------|------|
| `HUDNavigator.swiftpm/Package.swift` | Swift Playgrounds 用 |
| `Package.swift` | HUDCore（純粋ロジック）のテスト（Linux / macOS / Windows） |
| `project.yml` | XcodeGen → 正式アプリ（IPA）・iOS テスト |

```bash
swift test
```

## 構成

```
HUDNavigator.swiftpm/
├── Core/   純粋ロジック（Foundation のみ）：モデル、レイアウト、ルート進捗、案内、危険度、音声コマンド解析、Google Maps の解析 …
└── App/    iOS：AppModel、サービス（カメラ・位置・地図・音声・天気・AI・心拍計・同期 …）、UI（HUD・編集・ナビ・設定 …）
Extensions/Widgets/   ホーム画面ウィジェット・コントロールセンター（正式アプリの widgets 版のみ）
Tests/HUDCoreTests/   Core の XCTest（Linux）
AppTests/             iOS の XCTest・HUD スナップショット
```

## 計画書

| # | 資料 |
|---|------|
| 0 | [エグゼクティブサマリー](docs/00_summary.md) |
| 1 | [技術調査レポート](docs/01_technical_research.md) |
| 2 | [実現可能性一覧](docs/02_feasibility_matrix.md) |
| 3 | [推奨技術スタック](docs/03_tech_stack.md) |
| 4 | [アーキテクチャ設計](docs/04_architecture.md) |
| 5 | [ファイル・フォルダ構成](docs/05_file_structure.md) |
| 6 | [画面構成図](docs/06_screen_map.md) |
| 7 | [機能依存関係図](docs/07_dependency_graph.md) |
| 8 | [開発ロードマップ](docs/08_roadmap.md) |
| 9 | [テスト計画](docs/09_test_plan.md) |
| 10 | [無料・有料サービス一覧](docs/10_services_pricing.md) |
| 11 | [リスク・制約一覧](docs/11_risks_constraints.md) |
| 12 | [確認事項](docs/12_open_questions.md) |
| 13 | [ビルド・検証パイプライン](docs/13_ci_altstore_pipeline.md) |
| 14 | [実装状況](docs/14_implementation_status.md) |

## 安全

運転中は使用しないでください。物体認識・危険検知は実験的な補助機能で、安全装置ではありません。
