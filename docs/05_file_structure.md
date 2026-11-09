# 05. ファイル・フォルダ構成

改訂：GitHub Actions ＋ AltStore 方針（[13](13_ci_altstore_pipeline.md)）に合わせ、Xcode プロジェクトは **XcodeGen の `project.yml` から CI で生成**する。`.xcodeproj` はコミットしない（差分が読みにくく、Mac なしでは編集できないため）。

純粋ロジックは Swift Package **`HUDCore`** に分け、**Linux ランナーでも `swift test` できる**ようにする（速く・安く回せる）。

```
VitureHUD/                                ← このGitリポジトリ（公開）
├── README.md
├── project.yml                           ← XcodeGen 定義（ターゲット・Info.plist・権限説明・Bundle ID）
├── .github/
│   └── workflows/
│       ├── core-linux.yml                ← HUDCore のビルド・テスト（ubuntu）
│       ├── ios-ci.yml                    ← iOS ビルド＋シミュレータテスト＋スナップショット（macOS）
│       ├── device-build.yml              ← 未署名 IPA → GitHub Release（手動/タグ）
│       └── nightly.yml                   ← ネットワーク依存テスト（任意）
├── scripts/
│   ├── package_ipa.sh                    ← .app → Payload/ → .ipa
│   └── select_xcode.sh                   ← Xcode バージョン固定
├── docs/                                 ← 本計画書群・スパイク結果・実機テストレポート
│   └── device_reports/                   ← 実機テストモードが書き出した JSON の記録
├── Packages/
│   └── HUDCore/                          ← 純粋ロジック（Foundation のみ、Linux 対応）
│       ├── Package.swift
│       ├── Sources/HUDCore/
│       │   ├── Models/                   ← HUDLayout, HUDPanel, NormalizedRect, Theme, Preset,
│       │   │                               WidgetKind, RouteModels, Detection, Settings
│       │   ├── Engines/                  ← LayoutEngine, RouteProgressEngine, GuidancePlanner,
│       │   │                               HazardEvaluator, IntentParser, AlertPolicy, PowerPolicy
│       │   ├── Commands/                 ← AppCommand, CommandBus
│       │   └── Geo/                      ← 緯度経度・距離計算（CoreLocation 非依存の値型）、GPX 読み込み
│       └── Tests/HUDCoreTests/           ← XCTest（Linux / macOS 両対応）
│           └── Fixtures/                 ← GPX（架空ルート）、検出結果の記録 JSON、音声コマンド例文
├── App/                                  ← iOS アプリ本体（XcodeGen のアプリターゲット）
│   ├── HUDNavigatorApp.swift             ← @main
│   ├── AppDelegate.swift                 ← シーン構成
│   ├── ExternalSceneDelegate.swift       ← 外部ディスプレイ用シーン
│   ├── AppEnvironment.swift              ← サービス生成・依存注入
│   ├── AppState.swift                    ← 共有状態（@Observable, @MainActor）
│   ├── Services/                         ← OS API の窓口（プロトコル＋実装＋モック）
│   │   ├── Display/  Camera/  Vision/  Location/  Motion/  Device/
│   │   ├── Map/  Speech/  Weather/  Assistant/  Persistence/
│   │   └── Security/  Network/  Power/
│   ├── Features/
│   │   ├── Home/  HUD/（HUDRootView, Layers/, Editor/）  Widgets/
│   │   ├── Navigation/  VisionLab/  Assistant/  History/  Settings/
│   ├── DesignSystem/                     ← Tokens, BuiltInThemes, Components
│   ├── Diagnostics/
│   │   ├── DeviceTestMode/               ← 実機チェックリスト・計測・JSON 書き出し
│   │   ├── MetricsOverlay.swift          ← fps・温度・電池
│   │   └── LogViewer.swift
│   └── Resources/
│       ├── Models/                       ← Core ML モデル（Phase 4、ライセンス確認後）
│       ├── Localizable.xcstrings
│       └── Assets.xcassets
├── AppTests/                             ← iOS シミュレータで動く XCTest
│   ├── ServiceTests/                     ← モックを使ったサービス結合テスト
│   ├── SnapshotTests/                    ← ImageRenderer で HUD を PNG 化（1920×1080 / iPad / iPhone）
│   └── VisionRegressionTests/            ← 固定画像での物体認識回帰テスト
└── spikes/                               ← Phase 0 の使い捨て検証（必要な場合のみ）
```

## 依存の向き

```
App ──▶ HUDCore
AppTests ──▶ App, HUDCore
HUDCore ──▶ Foundation のみ（SwiftUI / UIKit / AVFoundation / CoreLocation / MapKit を import しない）
```

## 命名・コーディング規約（案）

- 型は英語（`HUDPanel`）、UI表示文字列は日本語（文字列カタログで管理）。
- 1ファイル1主要型。300行を超えたら分割を検討。
- ハードウェアを使うサービスには必ず **モック実装**（`MockLocationService` 等）を用意 → CI テストと GPX 再生に使う。
- 外部パッケージは原則使わない。XcodeGen は CI 上でのみ使うビルドツール（アプリには含まれない）。
- `swift format`（Swift 6 ツールチェーン同梱）で書式を統一し、CI で確認する。
