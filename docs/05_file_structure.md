# 05. ファイル・フォルダ構成

改訂（2026-11-09）：Q11 回答により **Swift Playgrounds（iPad・回数無制限のテスト）と GitHub Actions（正式 IPA）の両対応** とする。
ソースは `HUDNavigator.swiftpm/` の中の1か所だけに置き、3つのビルド定義がそれを参照する（詳細は [13](13_ci_altstore_pipeline.md) §9）。

| ビルド定義 | 使う場所 | 目的 |
|-----------|----------|------|
| `HUDNavigator.swiftpm/Package.swift` | iPad の Swift Playgrounds | 回数無制限の試作・テスト |
| `Package.swift`（リポジトリ直下） | GitHub Actions（Linux）、Windows（任意） | `HUDCore`（純粋ロジック）の XCTest |
| `project.yml`（XcodeGen） | GitHub Actions（macOS） | シミュレータテスト・スナップショット・未署名 IPA |

```
VitureHUD/                                ← このGitリポジトリ（公開）
├── README.md
├── Package.swift                         ← HUDCore テスト用（path: HUDNavigator.swiftpm/Core）
├── Tests/
│   └── HUDCoreTests/                     ← ロジックの XCTest（Linux / macOS / Windows）
│       └── Fixtures/                     ← 架空ルートの GPX、検出結果の記録 JSON、音声コマンド例文
├── project.yml                           ← XcodeGen：正式アプリ（Info.plist・権限説明・FULL_BUILD）
├── AppTests/                             ← iOS シミュレータで動く XCTest（CI のみ）
│   ├── ServiceTests/                     ← モックを使った結合テスト
│   ├── SnapshotTests/                    ← ImageRenderer で HUD を PNG 化（1920×1080 / iPad / iPhone）
│   └── VisionRegressionTests/            ← 固定画像での物体認識回帰テスト
├── .github/workflows/
│   ├── core-linux.yml                    ← HUDCore テスト（ubuntu）
│   ├── ios-ci.yml                        ← iOS ビルド＋テスト＋スナップショット＋ .swiftpm.zip 作成（macOS）
│   ├── device-build.yml                  ← 未署名 IPA → GitHub Release（手動/タグ）
│   └── nightly.yml                       ← ネットワーク依存テスト（任意）
├── scripts/
│   ├── package_ipa.sh                    ← .app → Payload/ → .ipa
│   ├── package_swiftpm.sh                ← Playgrounds 用 zip
│   ├── check_capabilities.sh             ← project.yml と .swiftpm の権限設定の一致確認
│   └── select_xcode.sh
├── docs/                                 ← 計画書・スパイク結果・テストレポート
│   └── device_reports/                   ← 実機テストモードの JSON 記録
└── HUDNavigator.swiftpm/                 ← ★ソース本体（iPad の Swift Playgrounds でそのまま開ける）
    ├── Package.swift                     ← Playgrounds 用（AppleProductTypes・Capabilities）
    ├── Core/                             ← 純粋ロジック（Foundation のみ・Linux 対応）
    │   ├── Models/                       ← HUDLayout, HUDPanel, NormalizedRect, Theme, Preset,
    │   │                                   WidgetKind, RouteModels, Detection, Settings
    │   ├── Engines/                      ← LayoutEngine, RouteProgressEngine, GuidancePlanner,
    │   │                                   HazardEvaluator, IntentParser, AlertPolicy, PowerPolicy
    │   ├── Commands/                     ← AppCommand, CommandBus
    │   └── Geo/                          ← 緯度経度・距離計算、GPX 読み込み
    └── App/
        ├── HUDNavigatorApp.swift         ← @main
        ├── AppDelegate.swift             ← シーン構成（コードで外部ディスプレイ用シーンを返す）
        ├── ExternalSceneDelegate.swift
        ├── AppEnvironment.swift          ← サービス生成・依存注入
        ├── AppState.swift                ← 共有状態（@Observable, @MainActor）
        ├── Services/                     ← Display / Camera / Vision / Location / Motion / Device /
        │                                   Map / Speech / Weather / Assistant / Persistence /
        │                                   Security / Network / Power（プロトコル＋実装＋モック）
        ├── Features/                     ← Home / HUD（HUDRootView, Layers, Editor）/ Widgets /
        │                                   Navigation / VisionLab / Assistant / History / Settings
        ├── DesignSystem/                 ← Tokens, BuiltInThemes, Components
        ├── FullBuildOnly/                ← App Intents など（#if FULL_BUILD）
        ├── Diagnostics/                  ← 実機テストモード（チェックリスト・計測・JSON 書き出し）、
        │                                   MetricsOverlay、LogViewer
        └── Resources/                    ← Core ML モデル（Phase 4）、文字列カタログ、アセット
```

## ルール

- `Core/` は `Foundation` 以外を import しない（SwiftUI / UIKit / AVFoundation / CoreLocation / MapKit 禁止）→ Linux / Windows でテストできる。
- App 側から `import HUDCore` は書かない（Playgrounds では Core と App が同じモジュールのため）。
- Playgrounds で動かない可能性のある機能は `App/FullBuildOnly/` に集め、`#if FULL_BUILD` で囲む。
- Swift Playgrounds が自動で書き換える `HUDNavigator.swiftpm/Package.swift` は、手で大きく変えない。
- ハードウェアを使うサービスには必ず **モック実装** を用意（CI テスト・GPX 再生用）。
- 外部パッケージは原則使わない（Playgrounds 互換・ライセンス・保守のため）。
- 型は英語、UI表示文字列は日本語。1ファイル1主要型。`swift format` で書式統一。
