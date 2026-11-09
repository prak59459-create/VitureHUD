# 01. 技術調査レポート

凡例：**【確認済】** 公開情報で確認 / **【要実機検証】** 仕様上可能だが本環境で未検証 / **【未確認】** 確認できず、断言しない

---

## 1. 開発環境：Swift Playgrounds

### 1-1. バージョン
- 公開情報で確認できた最新版は **Swift Playgrounds 4.7**（Swift 6 言語、iOS 26 SDK 同梱、iPadOS 18.0 以上が必要）【確認済：App Store 掲載情報】。
- 「Swift Playgrounds 6」という名前のバージョンは確認できなかった【未確認】。計画書の「6」は **Swift 6 言語** のことかもしれない → [Q1](12_open_questions.md)。
- 本計画では「Swift Playgrounds 4.7 以降 ＋ Swift 6 言語モード」を前提にする。Swift 6 の **厳格な並行性チェック**（`@MainActor`、`Sendable`）をアーキテクチャ設計に反映する（[04_architecture.md](04_architecture.md) §6）。

### 1-2. プロジェクト形式と制約
App プロジェクトは **`.swiftpm`（Swift Package 形式）** になる。`Package.swift` 内の `.iOSApplication` 製品定義でアプリ設定を持つ。

| 項目 | 状況 | 備考 |
|------|------|------|
| SwiftUI アプリ作成・実行 | 可能【確認済】 | iPad 上でビルド・実行・プレビュー |
| UIKit 併用（`UIViewRepresentable`、`UIApplicationDelegateAdaptor`） | 可能【確認済：SwiftUI標準機能】 | 外部ディスプレイ制御に必要 |
| カメラ・位置情報・マイク・モーション等の権限 | アプリ設定の「Capabilities」で追加可能【確認済：Apple公式に記載】 | 具体的な対象項目一覧は Phase 0 で画面を確認する |
| Swift Package 依存（GitHub等） | 追加可能【確認済】 | **バイナリ(XCFramework)依存は不安定・不可の可能性**【未確認】→ Google Maps SDK 導入に影響 |
| App Extension（WidgetKit、Live Activity、キーボード等） | **不可**【公開事例あり：widget不可の報告】 | ホーム画面ウィジェットは作れない。HUD内ウィジェットはアプリ内Viewなので問題なし |
| iCloud / CloudKit エンタイトルメント | **不可の可能性が高い**【公開事例・フォーラム報告。最新版は未確認】 | 同期は代替手段（§10） |
| WeatherKit エンタイトルメント | **不可の可能性が高い**【未確認】 | 有料Developer Program も必要。Open-Meteo で代替 |
| App Intents（ショートカット連携） | **【未確認】** | Phase 0 スパイク S0-7 で検証 |
| XCTest（ユニットテストターゲット） | **不可の可能性が高い**【未確認】 | アプリ内セルフテスト画面で代替（[09_test_plan.md](09_test_plan.md)） |
| Info.plist の直接編集 | 原則不可（Capabilities経由） | 外部ディスプレイ用シーンはコードで返す方式にする（§3） |
| Core ML の `.mlmodel` | Playgrounds ではコンパイル不可の可能性あり【未確認】 | **実行時に `MLModel.compileModel(at:)` でコンパイル**する方式なら動く見込み【要実機検証】 |
| git 連携 | Swift Playgrounds 自体にはない | 本リポジトリ ↔ iPad 間の受け渡し手段が必要（§1-3） |
| iPhone での実行 | **Swift Playgrounds は iPhone 版がない** | TestFlight（有料Developer Program）か Mac+Xcode が必要 |

### 1-3. コードの受け渡し（このリポジトリ ↔ iPad）
- 方法1：iPad の Git クライアントアプリ（例：Working Copy。無料版でclone/pull可、pushの可否・料金は要確認）でリポジトリを取得し、`.swiftpm` フォルダをファイルアプリ経由で Swift Playgrounds で開く。
- 方法2：GitHub から ZIP をダウンロード → ファイルアプリで展開 → Swift Playgrounds で開く（最も簡単・無料。iPad側の変更を戻すのが手間）。
- 推奨：**方法2で開始**し、往復が増えたら方法1を検討。

---

## 2. 対象端末の比較：iPad A16 と iPhone 15

| 項目 | iPad A16（第11世代, 2025） | iPhone 15 | 設計上の対応 |
|------|----------------------------|-----------|--------------|
| SoC | A16 Bionic | A16 Bionic | 同じ性能クラス。推論負荷は共通で調整可能 |
| 外部ディスプレイ | USB-C、ネイティブDisplayPort出力、外部ディスプレイ1台・最大4K60Hz【確認済】 | USB-C、DisplayPort出力対応【一般に知られた仕様。Phase 7で実機確認】 | 共通の外部ディスプレイ処理 |
| Stage Manager | 非対応（レビューで言及）【確認済】 | なし | 拡張デスクトップに頼らない。アプリ単位の外部シーン or ミラーリング |
| Apple Intelligence / Foundation Models | **非対応**【確認済】 | **非対応**（A16）【確認済】 | 端末内LLMは使わない |
| LiDAR | なし | なし（Proのみ） | 距離は推定値として扱う |
| 背面カメラ | 広角1基 | 広角＋超広角 | `AVCaptureDevice.DiscoverySession` で自動選択 |
| GPS | **Wi-Fiモデルは GPS非搭載**（Wi-Fi/周辺情報による概算位置）、Cellularモデルは GNSS搭載 | GNSS搭載 | **iPad Wi-Fiモデルではナビ精度の実機検証ができない** → [Q3](12_open_questions.md) |
| 気圧計 | 機種仕様要確認 | あり | 高度は任意機能にする |
| 画面 | 11インチ 4:3前後 | 6.1インチ 縦長 | レイアウトは正規化座標（0〜1）＋セーフエリアで管理 |
| 外部カメラ(UVC) | iPadOS 17以降で対応 | **非対応** | 外部カメラはiPad限定の任意機能 |
| USB-Cポート | 1基 | 1基 | グラス接続中は充電不可 → VITURE の給電アダプタ/Dock が必要 |

---

## 3. 外部ディスプレイ（VITURE）連携

### 3-1. VITURE Pro 2 の仕様（公開情報）
- 2026年8月発表、$299【確認済】
- Sony Micro-OLED、**1920×1080／片目**（左右合計3840×1080）、最大 **1600 nit**【確認済】
- 重量 約63g、**カメラなし**【確認済】
- 専用アプリ SpaceWalker（iOS / Android / macOS / Windows）【確認済】
- リフレッシュレート、3DoF表示の有無、iOSで出力される解像度（1080p/3D SBSなど）、電子調光の段階数は **【未確認】** → Phase 0 で実機確認
- **iOS アプリから IMU（頭部の向き）を読む公開SDK は確認できない**【未確認】。SpaceWalker の機能を他アプリから使える保証もない。

### 3-2. iOS 側の外部ディスプレイの動作
| 方式 | 内容 | 状況 |
|------|------|------|
| ミラーリング | 端末画面をそのままグラスに表示 | 標準動作【確認済】。iPad(4:3)→グラス(16:9)では左右に黒帯 → **黒=透明なのでHUD用途では問題にならない** |
| 独立外部画面 | アプリが外部ディスプレイ用の別画面を出す | UIKit の `UIWindowScene`（role: `windowExternalDisplayNonInteractive`）で実装する。`UIApplicationDelegate.application(_:configurationForConnecting:options:)` からコードで `UISceneConfiguration` を返せば Info.plist 編集なしで実装できる見込み【要実機検証】 |
| Swift Playgrounds 内実行時 | Playgrounds 本体がシーン管理を握っている可能性 | **独立外部画面が動かない可能性がある**【要実機検証：最大リスク】。TestFlight 版では動く可能性が高い |

**設計判断：** HUD描画は `HUDRootView` 1つにまとめ、「端末画面」「外部画面」のどちらにも同じViewを載せられるようにする。
- 独立外部画面が使える場合：グラス＝HUD、端末＝操作パネル
- 使えない場合：端末画面そのものをHUD表示にしてミラーリング（操作はHUD上のジェスチャー／音声／小型オーバーレイ）

### 3-3. 黒背景による光学透過
- VITURE は Micro-OLED＋光学系で、**黒(#000000)は発光しない＝現実が透けて見える**（加算合成型の表示）。HUD用途の前提として成立する。
- 注意点：
  - 暗い色（濃いグレー等）は「薄く見える／見えない」。**HUDには明るい色・高コントラストが必要**。
  - 透明度（アルファ）は「黒と混ぜる」効果になり、実際には「暗くなる」だけ。**半透明パネル背景は、グラス上ではほぼ見えない**（＝視界を妨げない利点でもある）。
  - 明るい屋外では表示が薄く見える。電子調光の操作はグラス本体側で、アプリからは制御できない【未確認・制御APIなし】。
  - 画面全体の明るさ（白い大面積）は視界を大きく遮る → テーマ設計で面積を制限。

### 3-4. 接続・切断・再接続
- `UIScene.willConnectNotification` / `didDisconnectNotification`、`UIScreen` の通知で検出【確認済：標準API】。
- 再接続時は保存済みのレイアウト・表示モードを復元する（DisplayManager が状態を保持）。

---

## 4. 背景表示システム

### 4-1. 黒背景モード
- `Color.black.ignoresSafeArea()` を最下層レイヤーとして描画。A。
- 端末画面側：**OLEDでないiPadでは黒も光る**。グラスへの出力には影響しない。

### 4-2. カメラパススルーモード
- AVFoundation（`AVCaptureSession` ＋ `AVCaptureVideoPreviewLayer`）で実装。A。
- 明るさ／コントラスト：プレビューレイヤーではなく、`AVCaptureVideoDataOutput` のフレームを Core Image / Metal で加工すると負荷が上がる。**まずはデバイス露出補正（`setExposureTargetBias`）とズーム（`videoZoomFactor`）で対応**し、コントラストは任意機能にする。
- 制約：
  - **iPad の Split View / Slide Over / ウィンドウ表示中はカメラが止まる**（マルチタスクでのカメラ利用は条件付き）。HUDはフルスクリーン前提。
  - アプリがバックグラウンドに回るとカメラは停止する【確認済：iOS仕様】。
  - 端末カメラの向き＝頭の向きではない。**光学透過グラスにカメラ映像を重ねると二重に見える**。カメラモードは「端末画面で使う」「グラスの調光を最大にして使う」用途が中心になる。
  - 遅延：一般に数十〜100ms以上。Phase 1 で計測（[09_test_plan.md](09_test_plan.md) T-CAM-02）。

---

## 5. HUDシステム
- SwiftUI の `ZStack` レイヤー＋ `DragGesture` / `MagnifyGesture` で自由配置・サイズ変更。A。
- 解像度の違い（iPad / iPhone / 1080p外部画面）に対応するため、**パネル位置・サイズは正規化座標（0.0〜1.0）で保存**し、描画時にキャンバスサイズを掛ける。
- 自動整列：グリッドスナップ＋矩形の重なり判定（純粋なロジックなのでテストしやすい）。
- 発光表現：`shadow(color:radius:)` の重ね掛け。描画負荷が高いので、パネル数×発光の上限を設ける。
- テーマ：`Codable` な構造体 → JSONとしてインポート／エクスポート（ファイル共有で配布可能）。

---

## 6. ナビゲーション

### 6-1. Apple MapKit【主軸】
| 機能 | 状況 |
|------|------|
| 2D/3D地図（SwiftUI `Map`、`MapCamera`、ピッチ） | A |
| 現在地・追従・進行方向アップ（`MapUserLocationButton`、`userTrackingMode` 相当） | A |
| 施設名・住所検索（`MKLocalSearch`、`MKLocalSearchCompleter`）、地図タップ（`MapReader`）、逆ジオコーディング | A |
| ルート検索 徒歩／自動車（`MKDirections`）、複数ルート（`requestsAlternateRoutes`）、距離・所要時間・ETA・ステップ（指示文・距離） | A |
| 公共交通 | **ETAのみ取得可、経路の詳細ステップは取得できない**（`calculateETA` は transit 対応、`calculate` は非対応）【既知の仕様。Phase 3で再確認】 → 「Apple マップで開く」連携を代替案にする |
| 自転車 | iOSバージョンによる。【未確認】 |
| ターンバイターン案内 | MapKit に案内エンジンはない → **ステップと現在地から自前で進捗計算**（RouteProgressEngine） |
| 料金 | 無料（アプリ単位の利用量制限あり）【既知】 |
| 道路名 | ステップの指示文に含まれることがある。個別フィールドとしては保証されない |
| Look Around | 対応地域のみ。任意機能 |

### 6-2. Google Maps【任意・後回し】
- Maps SDK for iOS（地図表示）は **無料・利用量無制限** とされる【第三者情報。公式で要確認】。**APIキーと請求先アカウント（クレジットカード）登録が必要**。
- ルート（Routes API）・場所検索（Places API）は **従量課金**。2025年3月以降は SKUごとの無料枠（Essentials 月10,000件など）【第三者情報・要確認】。
- Navigation SDK（ターンバイターン）は別契約・有料。
- 導入の技術課題：SDK はバイナリ配布 → **Swift Playgrounds でバイナリ依存を扱えるか【未確認】**。
- 判断：**Phase 3 は MapKit のみ**。`MapProvider` / `RoutingProvider` プロトコルで抽象化しておき、Google 対応は Phase 6 以降に可否判断。

### 6-3. 音声案内
- `AVSpeechSynthesizer`（日本語音声あり、無料・オフライン）。A。
- `AVAudioSession` を `.playback` + `.duckOthers` にして音楽を一時的に下げる。
- 画面ロック中・バックグラウンドでの継続にはバックグラウンドモード（audio / location）が必要 → Capabilities で設定できるか【要実機検証】。HUD利用時はアプリが前面にある前提なので Phase 3 では必須にしない。
- 「AI音声」：無料かつ端末内で動く高品質TTSは限られる。`AVSpeechSynthesisVoice` の拡張音声（設定アプリからダウンロード）を第一候補。クラウドTTSは有料が多い。

---

## 7. センサー

| センサー | API | 権限 | 分類 | 注意 |
|----------|-----|------|------|------|
| 位置・速度・移動距離 | CoreLocation `CLLocationUpdate.liveUpdates()` / `CLLocationManager` | 位置情報（使用中） | A | iPad Wi-Fiモデルは GPS非搭載。速度は `speed < 0` で無効値 |
| 方位（コンパス） | `CLLocationManager.startUpdatingHeading` | 位置情報 | A | 磁気干渉。`headingAccuracy` を表示 |
| 加速度・ジャイロ・姿勢 | CoreMotion `CMMotionManager.deviceMotion` | 不要 | A | 更新頻度を可変に（省電力） |
| 歩行/静止などの活動推定 | `CMMotionActivityManager` | モーションと運動 | B | 権限説明が必要。iPadでの対応状況要確認 |
| 歩数・距離 | `CMPedometer` | モーションと運動 | B | 同上 |
| 気圧・相対高度 | `CMAltimeter` | 不要/要 | B | 機種依存 |
| バッテリー | `UIDevice.batteryLevel/State` | 不要 | A | 1%単位ではなく5%刻み程度になることがある |
| 発熱状態 | `ProcessInfo.thermalState` | 不要 | A | 省電力制御のトリガーに使う |
| 低電力モード | `ProcessInfo.isLowPowerModeEnabled` | 不要 | A | アプリから低電力モードをONにはできない（提案のみ） |
| AirPods 頭部の動き | `CMHeadphoneMotionManager` | モーション | B | **対応AirPods使用時、頭の向きを取得できる** → VITUREのIMUの代替候補（任意機能） |

---

## 8. AIビジョン

| 対象 | 方法 | 分類 | 備考 |
|------|------|------|------|
| 歩行者（人） | Vision `VNDetectHumanRectanglesRequest` | A | 内蔵・無料 |
| 動物 | Vision `VNDetectAnimalRectanglesRequest` | A | **犬・猫のみ** |
| 文字（標識の文字など） | Vision `VNRecognizeTextRequest`（日本語対応） | A | 標識の「種類」識別ではない |
| 画像分類（シーン） | Vision `VNClassifyImageRequest` | A | 位置（枠）は出ない |
| 自動車・自転車・バイク・その他物体 | Core ML 物体検出モデル（YOLO系 / SSD系） | B | モデル同梱が必要。**ライセンス確認必須**（後述） |
| 道路標識の種類 | 専用学習モデルが必要 | C | 日本の標識データセット・学習が必要 |
| 車線 | 専用モデル or 画像処理 | D | 歩行者視点・手持ちカメラでは実用精度が出にくい |
| 距離 | LiDARなし → 単眼推定 | D | 「目安」としてのみ表示。断定しない |
| 接近・衝突リスク | 枠の拡大率から接触までの時間を推定（TTC） | B（実験） | 誤検知・検知漏れ前提。**安全装置ではない** |

**モデルのライセンス注意：**
- Ultralytics YOLOv5/v8/11 は **AGPL-3.0**（アプリ配布時にソースコード公開義務が生じうる。商用ライセンスは有料）。
- Apple の Core ML モデル配布ページのモデル（YOLOv3 等）や、Apache-2.0 等のモデルを優先して候補にする。採用前に各モデルのライセンスを個別に確認する【未確認：Phase 4 で確定】。

**性能目安：** A16 の Neural Engine で小型検出モデルは数〜十数fps程度が期待できるが【要実機検証】、カメラ＋外部出力＋GPSと同時実行時の発熱が課題。推論は 5〜10fps に間引く設計にする。

---

## 9. 音声認識・AIアシスタント

### 9-1. 音声認識
- `SFSpeechRecognizer`（日本語、`requiresOnDeviceRecognition` で端末内処理）【A16での日本語端末内認識は要実機検証】。
- iOS 26 の新しい `SpeechAnalyzer` / `SpeechTranscriber` も候補。対応言語・端末要件を Phase 5 で確認【未確認】。
- 権限：マイク＋音声認識。

### 9-2. 音声コマンド（端末内・無料）
- 認識テキスト → **ルールベースの意図解析（IntentParser）** → `AppCommand`（例：`.setBackground(.black)`、`.startNavigation`、`.applyPreset("ミニマル")`）。
- 計画書の例（「黒背景に変更して」「速度を表示して」等）は **ルールベースで十分に実現可能**。

### 9-3. 会話型AI
- **端末内LLM：Apple Foundation Models は A16 非対応（E）**。オープンモデル（MLX / llama.cpp 等）を端末で動かす方法は、Swift Playgrounds でのビルド（Metalシェーダ・C++）が困難で、メモリ6GB級端末では負荷も大きい（D）。
- **クラウドLLM（C）**：ユーザーが自分のAPIキーを入力した場合のみ有効化。
  - Google Gemini API：無料枠あり（レート制限あり、**無料枠では入力データが品質改善に使われる場合がある**）【要確認】
  - Anthropic Claude API / OpenAI API：従量課金
  - 送信するのは「音声認識後のテキスト＋必要最小限の状況（例：目的地名）」のみ。**位置座標・カメラ画像は既定で送らない**。
- APIキーは Keychain に保存（端末外に出さない）。

---

## 10. 天気・周辺施設・同期・ショートカット

| 機能 | 推奨手段 | 分類 | 備考 |
|------|----------|------|------|
| 天気・気温・降水確率・降水量・湿度・風・UV | **Open-Meteo Forecast API** | C（無料・キー不要） | **非商用のみ無料**、データは CC BY 4.0 → 出典表示が必要。商用は有料プラン |
| 空気質（PM2.5等） | Open-Meteo Air Quality API | C | 同上 |
| WeatherKit | 有料Developer Program＋エンタイトルメント | D（Playgrounds） | Xcode移行後の選択肢 |
| 周辺施設 | `MKLocalSearch` ＋ `MKPointOfInterestCategory` | A | **営業時間・評価は MapKit では基本的に取得できない**。必要なら Google Places（有料） |
| 端末内保存 | JSON（設定・テーマ）、SwiftData または JSON Lines（履歴） | A / B | SwiftData は Playgrounds で動くか要検証 |
| iPad↔iPhone 同期 | **設定一式を JSON でエクスポート → iCloud Drive（ファイルアプリ）に保存 → 他端末でインポート** | B | エンタイトルメント不要。自動同期ではない |
| CloudKit / iCloud Key-Value 自動同期 | エンタイトルメント必要 | D（Playgrounds） | Xcode 移行後に対応 |
| Appleショートカット | App Intents | B【未確認】 | Playgrounds で動かない場合、URLスキーム等の代替も Info.plist 制約で困難 → Xcode 移行課題 |
| ホーム画面ウィジェット | WidgetKit（拡張） | D | HUD内ウィジェットとは別物 |
| Apple Watch アプリ | watchOS ターゲット | D | Playgrounds 不可 |
| AirPods | 音声出力・ヘッドトラッキング | A / B | — |
| Bluetoothセンサー（心拍等） | CoreBluetooth（標準GATTプロファイル） | C | 権限と機器が必要 |

---

## 11. バックグラウンド処理
- HUD は **アプリ前面での利用が前提**。iPhone をロックすると外部ディスプレイ出力も止まる。
- 端末画面を暗くして消費電力を下げる：`UIScreen.brightness` の調整（iPhone）と `isIdleTimerDisabled = true`（自動ロック防止）。
- バックグラウンドでの位置更新・音声案内は Phase 6 以降の任意機能（Capabilities 設定可否を検証）。

---

## 12. 参照情報
- [VITURE Pro 2 – B&H](https://www.bhphotovideo.com/c/product/1996511-REG/viture_pfs6001a1a_pro_2_xr_glasses.html)
- [VITURE Pro 2 review – Digital Trends](https://www.digitaltrends.com/computing/viture-pro-2-review/)
- [VITURE Pro 2 – The Gadgeteer](https://the-gadgeteer.com/2026/08/06/viture-pro-2-xr-glasses/)
- [VITURE Pro 2 specs – TechEBlog](https://www.techeblog.com/viture-pro-2-xr-ar-glasses-specs-price-review/)
- [VITURE Pro 2 – JB Hi-Fi（SpaceWalker対応OS）](https://www.jbhifi.com.au/products/viture-pro-2-xr-glasses)
- [iPad (A16) 技術仕様 – Apple サポート](https://support.apple.com/en-bh/122240)
- [iPad (A16) review – Engadget](https://www.engadget.com/mobile/tablets/ipad-2025-with-a16-review-no-apple-intelligence-no-problem-132641539.html)
- [iPad A16 review – Macworld](https://www.macworld.com/article/2646985/ipad-a16-review.html)
- [Swift Playground – App Store](https://apps.apple.com/lu/app/id908519492)
- [Swift Playgrounds – Apple Developer](https://developer.apple.com/swift-playground/)
- [WWDC22: Build your first app in Swift Playgrounds](https://developer.apple.com/videos/play/wwdc2022-110348)
- [iPadだけでApp Store公開までの事例（widget・CloudKit不可の言及）](https://www.cephalopod.studio/blog/lessons-from-developing-an-app-on-the-ipad-from-start-to-finish-on-the-app-store)
- [Apple Developer Forums: CloudKit と Swift Playgrounds](https://developer.apple.com/forums/thread/697378)
- [Google Maps Platform 料金](https://developers.google.com/maps/billing-and-pricing/pricing)
- [Is Google Maps API Free in 2026? – Woosmap（第三者）](https://www.woosmap.com/blog/is-google-maps-api-free)
- [Open-Meteo](https://open-meteo.com/) / [Open-Meteo 利用規約](https://open-meteo.com/en/terms)
