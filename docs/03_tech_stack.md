# 03. 推奨技術スタック

## 1. 基本

| 項目 | 採用 | 理由 |
|------|------|------|
| ビルド・テスト | **GitHub Actions**（`ubuntu-latest`＋`macos-26`、Xcode 26 系を固定） | 公開リポジトリは無料。Mac 不要（[13](13_ci_altstore_pipeline.md)） |
| プロジェクト生成 | **XcodeGen**（`project.yml` → `.xcodeproj`、CI 上で生成） | Info.plist・権限・シーン設定をテキストで管理できる |
| 実機インストール | **AltStore**（無料 Apple ID で署名、7日ごとに更新） | iPad A16・iPhone 15 の両方に入れられる |
| iPad での日常テスト | **Swift Playgrounds**（同じソースの `.swiftpm` を開く） | 回数無制限で iPad 実機テスト（[13](13_ci_altstore_pipeline.md) §0） |
| 言語 | Swift 6（言語モード 6） | 厳格な並行性チェックでデータ競合を防ぐ |
| テスト | XCTest（`HUDCore` は Linux / macOS、アプリは iOS シミュレータ） | CI で自動実行 |
| UI | SwiftUI（主）＋ UIKit（外部ディスプレイのシーン管理、カメラプレビュー） | SwiftUI だけでは外部画面シーンを細かく制御できないため |
| 最低対応OS | **iOS / iPadOS 18.0** | `@Observable`、`Map` の新API、`CLLocationUpdate` が使える。両端末とも iOS 26 まで対応 |
| 状態管理 | Observation（`@Observable`）＋ 依存注入用の `AppEnvironment` | iOS 17+ 標準。外部画面と端末画面で同じ状態を共有しやすい |
| 非同期 | Swift Concurrency（`async/await`、`AsyncStream`、`actor`） | センサーストリームの統一 |
| プロジェクト形式 | アプリターゲット1つ（App Extension なし）＋ Swift Package `HUDCore` | AltStore 無料アカウントの App ID 上限を消費しない |
| 外部パッケージ | **原則なし**（Phase 0〜5） | ライセンス・保守のリスクを避ける |

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

## 4. GitHub Actions＋Xcode ビルドへの移行で使えるようになったもの

- Info.plist の細かな設定（外部ディスプレイ用シーン、バックグラウンドモード）、XCTest、`.mlmodel` のビルド時コンパイル、App Intents のメタデータ生成、Swift Package のバイナリ依存（Google Maps SDK 等）

## 5. 有料 Apple Developer Program に加入した場合に解放されるもの

- CloudKit による自動同期、WeatherKit、1年署名（7日更新が不要）、TestFlight、App Extension（ウィジェット）を App ID 上限を気にせず追加

アーキテクチャはこの移行を想定し、**サービスをプロトコルで抽象化**しておく（例：`SyncService` を「ファイル同期版」→「CloudKit版」に差し替え可能）。
