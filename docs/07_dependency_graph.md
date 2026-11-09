# 07. 機能依存関係図

矢印は「A → B」＝「B は A が完成していることを前提とする」。

```mermaid
flowchart TD
    classDef p1 fill:#1f6feb,color:#fff
    classDef p2 fill:#8957e5,color:#fff
    classDef p3 fill:#2da44e,color:#fff
    classDef p4 fill:#bf8700,color:#fff
    classDef p5 fill:#cf222e,color:#fff
    classDef p6 fill:#57606a,color:#fff

    S0["Phase 0 スパイク結果<br/>(外部画面方式・権限・モデル読込)"]

    State["AppState / AppEnvironment / CommandBus"]:::p1
    Display["DisplayManager<br/>外部ディスプレイ"]:::p1
    BG["背景レイヤー<br/>黒/カメラ"]:::p1
    Panel["HUDパネル基盤<br/>正規化座標・移動・サイズ"]:::p1
    Persist["PersistenceService<br/>(JSON保存)"]:::p1
    Diag["診断・実機テストモード・メトリクス"]:::p1

    Theme["テーマ・スタイル"]:::p2
    Layout["LayoutEngine<br/>整列・スナップ"]:::p2
    Widget["WidgetRegistry<br/>標準ウィジェット"]:::p2
    Preset["プリセット"]:::p2

    Loc["LocationService"]:::p3
    Map["MapProvider(MapKit)"]:::p3
    Route["RoutingProvider + RouteProgressEngine"]:::p3
    Voice["VoiceGuidanceService"]:::p3
    MiniMap["ミニマップ・次の曲がり角ウィジェット"]:::p3

    Motion["MotionService / Battery / Power"]:::p4
    Cam["CameraService(フレーム出力)"]:::p4
    Detect["DetectionService(Vision/CoreML)"]:::p4
    Hazard["HazardEvaluator + 警告"]:::p4

    STT["SpeechInputService"]:::p5
    Intent["IntentParser → AppCommand"]:::p5
    LLM["AssistantProvider(クラウド任意)"]:::p5
    Net["NetworkGateway"]:::p5

    Weather["WeatherProvider(Open-Meteo)"]:::p6
    Alert["AlertPolicy / 通知"]:::p6
    History["履歴・分析"]:::p6
    Sync["SyncService(ファイル)"]:::p6
    Intents["App Intents"]:::p6

    S0 --> State & Display & BG
    State --> Panel & Persist
    Display --> Panel
    BG --> Panel
    Panel --> Theme & Layout & Widget
    Persist --> Preset
    Theme & Widget & Layout --> Preset

    Loc --> Map --> Route --> Voice
    Route --> MiniMap
    Widget --> MiniMap

    Motion --> Hazard
    BG --> Cam --> Detect --> Hazard
    Alert --> Hazard

    STT --> Intent
    State --> Intent
    Net --> LLM
    Intent --> LLM

    Net --> Weather --> Widget
    Persist --> History & Sync
    Loc --> History
    State --> Intents

    Motion -.省電力.-> Cam & Detect & Loc
```

## クリティカルパス

1. **S0-1（外部ディスプレイ方式の確定）→ DisplayManager → HUDパネル基盤**
   ここが決まらないと HUD 全体の作り方（端末画面の役割）が決まらない。
2. **LocationService → RoutingProvider → RouteProgressEngine → 音声案内**
   ナビ機能の骨格。iPad Wi-Fi モデルでは GPS 精度の検証ができないため、**位置のシミュレーション再生（記録したGPXの再生）** を先に用意する。
3. **CameraService(フレーム出力) → DetectionService → HazardEvaluator**
   Phase 4。モデルのライセンス確定と S0-5（モデル読込）が前提。

## 独立して並行できるもの

- テーマ・デザイン（Phase 2）と、ナビのロジック（RouteProgressEngine）は互いに依存しない。
- IntentParser（音声コマンド解析）は純粋ロジックなので、音声認識より先に作ってテキスト入力でテストできる。
- Open-Meteo 連携は他機能と独立。
