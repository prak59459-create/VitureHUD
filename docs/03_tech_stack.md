# 03. 推奨技術スタック

## 1. 基本

| 項目 | 採用 | 理由 |
|------|------|------|
| 開発環境 | Swift Playgrounds 4.7 以降（iPad A16） | 計画書の指定。Swift 6 / iOS 26 SDK 同梱 |
| 言語 | Swift 6（言語モード 6） | 厳格な並行性チェックでデータ競合を防ぐ |
| UI | SwiftUI（主）＋ UIKit（外部ディスプレイのシーン管理、カメラプレビュー） | SwiftUI だけでは外部画面シーンを細かく制御できないため |
| 最低対応OS | **iOS / iPadOS 18.0** | Swift Playgrounds 4.7 の動作要件と揃える。`@Observable`、`Map` の新API、`CLLocationUpdate` が使える |
| 状態管理 | Observation（`@Observable`）＋ 依存注入用の `AppEnvironment` | iOS 17+ 標準。外部画面と端末画面で同じ状態を共有しやすい |
| 非同期 | Swift Concurrency（`async/await`、`AsyncStream`、`actor`） | センサーストリームの統一 |
| プロジェクト形式 | `.swiftpm` App プロジェクト（単一アプリターゲット＋フォルダで層分け） | Playgrounds の制約に合わせる |
| 外部パッケージ | **原則なし**（Phase 0〜5） | Playgrounds 互換性・ライセンス・保守のリスクを避ける |

## 2. 機能別フレームワーク

| 機能 | フレームワーク / API | 料金 |
|------|---------------------|------|
| HUD描画 | SwiftUI（`ZStack`、`Canvas`、`GeometryReader`） | 無料 |
| 外部ディスプレイ | UIKit `UIWindowScene`（外部ディスプレイ用ロール）、`UIHostingController` | 無料 |
| カメラ | AVFoundation（`AVCaptureSession`、`AVCaptureVideoPreviewLayer`、`AVCaptureVideoDataOutput`） | 無料 |
| 映像処理 | Core Image（必要時のみ） | 無料 |
| 物体認識 | Vision（人・犬猫・文字）、Core ML（物体検出モデル） | 無料（モデルのライセンスは個別確認） |
| 地図・検索・ルート | MapKit（SwiftUI `Map`、`MKLocalSearch`、`MKDirections`） | 無料（利用量制限あり） |
| 位置情報・方位 | CoreLocation（`CLLocationUpdate`、`CLLocationManager`） | 無料 |
| モーション | CoreMotion（`CMMotionManager`、`CMMotionActivityManager`、`CMPedometer`、`CMHeadphoneMotionManager`） | 無料 |
| 音声合成 | AVFoundation `AVSpeechSynthesizer` | 無料 |
| 音声認識 | Speech（`SFSpeechRecognizer`、iOS 26 では `SpeechAnalyzer` も検討） | 無料（端末内） |
| ネットワーク | `URLSession`、Network `NWPathMonitor` | 無料 |
| 天気 | Open-Meteo REST API（`URLSession`） | 非商用無料 |
| 保存 | `Codable` ＋ JSON ファイル（Application Support）、履歴は SwiftData【要検証】または JSON Lines | 無料 |
| 秘密情報 | Security（Keychain） | 無料 |
| グラフ | Swift Charts | 無料 |
| 通知 | UserNotifications（ローカル通知） | 無料 |
| ショートカット | App Intents【Playgroundsでの可否要検証】 | 無料 |
| ログ | `os.Logger` ＋ アプリ内ログビューア | 無料 |

## 3. 採用しない／後回しにするもの

| 候補 | 判断 | 理由 |
|------|------|------|
| Apple Foundation Models | 不採用 | A16 非対応 |
| Google Maps SDK / Routes / Places | 後回し（Phase 6以降に判断） | APIキー・請求登録・従量課金、Playgroundsでのバイナリ依存が未確認 |
| WeatherKit | 後回し | 有料Developer Program、エンタイトルメント |
| CloudKit | 後回し | Playgroundsでエンタイトルメント不可の可能性 |
| ARKit | 基本不採用 | 背面カメラのAR座標は「端末の向き」でありグラス視点と一致しない。用途が限られる |
| RealityKit | 不採用 | 2D HUD中心のため不要 |
| サードパーティ製 UI ライブラリ | 不採用 | 依存を増やさない |
| Ultralytics YOLO 系モデル | 原則不採用 | AGPL-3.0（ソース公開義務）。代替モデルを優先 |

## 4. 将来 Xcode（Mac）へ移行した場合に解放されるもの

- CloudKit による自動同期、WeatherKit、WidgetKit（ホーム画面ウィジェット／ロック画面）、watchOS アプリ、Info.plist の細かな設定、XCTest によるユニットテスト、Swift Package のバイナリ依存（Google Maps SDK）

アーキテクチャはこの移行を想定し、**サービスをプロトコルで抽象化**しておく（例：`SyncService` を「ファイル同期版」→「CloudKit版」に差し替え可能）。
