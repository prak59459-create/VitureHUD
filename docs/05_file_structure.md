# 05. ファイル・フォルダ構成

Swift Playgrounds の App プロジェクト（`.swiftpm`）は1つのアプリターゲットが基本のため、**フォルダで層を分ける**。
Xcode へ移行する場合は `Domain/` をそのまま Swift Package（`HUDCore`）に切り出せるよう、`Domain/` は UIKit / SwiftUI / ハードウェアに依存させない。

```
VitureHUD/                              ← このGitリポジトリ
├── README.md
├── docs/                               ← 本計画書群
├── spikes/                             ← Phase 0 の使い捨て検証アプリ（本体とは別）
│   ├── S0-1_ExternalDisplay.swiftpm
│   ├── S0-3_CameraPlusDisplay.swiftpm
│   └── ...
└── HUDNavigator.swiftpm/               ← 本体（Phase 1 から作成）
    ├── Package.swift                   ← アプリ設定・Capabilities（Playgroundsが管理）
    ├── App/
    │   ├── HUDNavigatorApp.swift       ← @main
    │   ├── AppDelegate.swift           ← 外部ディスプレイ用シーン構成
    │   ├── ExternalSceneDelegate.swift
    │   ├── AppEnvironment.swift        ← サービスの生成・依存注入
    │   └── AppState.swift              ← 共有状態（@Observable, @MainActor）
    ├── Domain/                         ← 純粋ロジック（UI・OS非依存）
    │   ├── Models/
    │   │   ├── HUDLayout.swift
    │   │   ├── HUDPanel.swift
    │   │   ├── NormalizedRect.swift
    │   │   ├── Theme.swift
    │   │   ├── Preset.swift
    │   │   ├── WidgetKind.swift
    │   │   ├── RouteModels.swift
    │   │   ├── Detection.swift
    │   │   └── SettingsModels.swift
    │   ├── Engines/
    │   │   ├── LayoutEngine.swift      ← スナップ・整列・重なり防止
    │   │   ├── RouteProgressEngine.swift ← 残り距離・次の曲がり角・逸脱検知
    │   │   ├── GuidancePlanner.swift   ← いつ何を読み上げるか
    │   │   ├── HazardEvaluator.swift   ← 接近・危険度（実験）
    │   │   ├── IntentParser.swift      ← 音声テキスト→AppCommand
    │   │   └── AlertPolicy.swift       ← 通知の優先度・抑制
    │   └── Commands/
    │       ├── AppCommand.swift
    │       └── CommandBus.swift
    ├── Services/                       ← OS API・外部APIの窓口（プロトコル＋実装）
    │   ├── Display/DisplayManager.swift
    │   ├── Camera/CameraService.swift
    │   ├── Vision/DetectionService.swift
    │   ├── Vision/ModelLoader.swift    ← .mlmodel の実行時コンパイル
    │   ├── Location/LocationService.swift
    │   ├── Motion/MotionService.swift
    │   ├── Device/BatteryService.swift
    │   ├── Map/MapProvider.swift       ← protocol
    │   ├── Map/MapKitProvider.swift
    │   ├── Map/RoutingProvider.swift   ← protocol + MapKit実装
    │   ├── Speech/VoiceGuidanceService.swift
    │   ├── Speech/SpeechInputService.swift
    │   ├── Weather/WeatherProvider.swift ← protocol
    │   ├── Weather/OpenMeteoProvider.swift
    │   ├── Assistant/AssistantProvider.swift ← protocol（ローカル/クラウド）
    │   ├── Persistence/PersistenceService.swift
    │   ├── Persistence/SyncService.swift ← protocol（ファイル同期/将来CloudKit）
    │   ├── Security/KeychainStore.swift
    │   ├── Network/NetworkGateway.swift
    │   └── Power/PowerGovernor.swift
    ├── Features/                       ← 画面ごとの View + ViewModel
    │   ├── Home/
    │   ├── HUD/
    │   │   ├── HUDRootView.swift       ← 端末・外部画面で共通のHUD
    │   │   ├── Layers/BackgroundLayer.swift
    │   │   ├── Layers/DetectionOverlay.swift
    │   │   ├── Layers/PanelLayer.swift
    │   │   ├── Layers/AlertLayer.swift
    │   │   ├── Layers/SystemIndicatorLayer.swift
    │   │   └── Editor/HUDEditorView.swift
    │   ├── Widgets/                    ← 各ウィジェットのView（WidgetRegistry）
    │   ├── Navigation/
    │   ├── VisionLab/
    │   ├── Assistant/
    │   ├── History/
    │   └── Settings/                   ← 表示・地図・通知・同期・プライバシー・詳細
    ├── DesignSystem/
    │   ├── Tokens.swift                ← 色・文字サイズ・余白
    │   ├── BuiltInThemes.swift
    │   └── Components/
    ├── Diagnostics/
    │   ├── SelfTestRunner.swift        ← アプリ内テスト（XCTest代替）
    │   ├── SelfTests/*.swift
    │   ├── MetricsOverlay.swift        ← fps・温度・電池の表示
    │   └── LogViewer.swift
    └── Resources/
        ├── Models/                     ← Core ML モデル（Phase 4、ライセンス確認後）
        └── Localizable.xcstrings       ← 日本語（＋将来英語）
```

## 命名・コーディング規約（案）

- 型は英語（`HUDPanel`）、UI表示文字列は日本語（文字列カタログで管理）。
- 1ファイル1主要型。300行を超えたら分割を検討。
- `Domain/` から `import SwiftUI` / `UIKit` / `AVFoundation` / `CoreLocation` をしない（座標などは独自の値型で表す）。
- ハードウェアを使うサービスには必ず **モック実装**（`MockLocationService` 等）を用意 → シミュレーション再生やセルフテストに使う。
