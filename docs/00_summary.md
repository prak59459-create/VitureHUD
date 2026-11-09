# 00. エグゼクティブサマリー

調査日：2026-11-09
対象計画書：「VITURE対応 AIスマートHUDナビゲーションアプリ 開発計画書」

本資料群の記述ルール：
- **【確認済】** … 公式情報・複数の公開情報で確認できたもの
- **【要実機検証】** … 仕様上は可能と考えられるが、本プロジェクトの環境（Swift Playgrounds・VITURE実機）で動くか未確認のもの
- **【未確認】** … 公開情報で確認できなかったもの。実現可能と断言しない

---

## 1. 結論（先に要点）

1. **HUDの中核（黒背景HUD・カメラ背景・自由配置パネル・MapKitナビ・センサー・音声案内）は、通常のiOS APIで実現可能（A〜B）。** 無料で作れる範囲が大きい。
2. **最大の技術リスクは「Swift Playgrounds 上で外部ディスプレイの独立表示が動くか」**。Swift Playgrounds 内で実行中のアプリは Playgrounds 本体のプロセス／シーン管理の影響を受ける可能性があり【要実機検証】。
   → 対策として **「ミラーリングでも成立するHUD設計」** を最初から採用する。黒背景はVITURE上で透明に見えるため、ミラーリング時の黒帯（ピラーボックス）も問題にならない。
3. **iPhone 15 へのインストール経路が要確認。** Swift Playgrounds は iPad / Mac 用アプリで、iPhone 版はない。iPhone 15 で動かすには次のいずれかが必要：
   - (a) Apple Developer Program（年額・有料）に加入し、Swift Playgrounds から App Store Connect にアップロード → TestFlight で iPhone にインストール
   - (b) Mac + Xcode でビルドして iPhone に転送（無料のApple IDでも可能だが、署名の有効期限は7日）
4. **端末内の生成AI（Apple Foundation Models / Apple Intelligence）は iPad A16・iPhone 15 のどちらでも使えない**【確認済：A16 は Apple Intelligence 非対応】。
   → AIアシスタントは「端末内のルールベース音声コマンド（無料・オフライン）」＋「任意で使うクラウドLLM（ユーザーが用意したAPIキー）」の二段構成にする。
5. **VITURE Pro 2 は実在する製品**【確認済：2026年8月発表、1920×1080/片目 Micro-OLED、最大1600nit、カメラなし、約63g】。ただし iOS アプリから **頭部トラッキング（IMU）値を取得する公開APIは確認できない**【未確認】。iOS 側からは「USB-C 外部ディスプレイ」として扱う前提で設計する。
6. **Google Maps・iCloud(CloudKit)・WeatherKit・ホーム画面ウィジェット(WidgetKit)・Apple Watch は、Swift Playgrounds 単体では導入が難しい／不可（C〜D）。** Phase 6 以降、Xcode 移行の要否とあわせて判断する。代替案は各資料に記載。
7. **「Swift Playgrounds 6」という名称のバージョンは公開情報で確認できなかった。** 確認できた最新は Swift Playgrounds **4.7（Swift 6 言語・iOS 26 SDK 同梱、iPadOS 18 以上）**。計画書の「6」は Swift 6 を指している可能性があるため確認したい（[12_open_questions.md](12_open_questions.md) Q1）。

## 2. 分類の集計（詳細は [02_feasibility_matrix.md](02_feasibility_matrix.md)）

| 分類 | 意味 | 主な機能 |
|------|------|----------|
| A | 通常のiOSアプリで実現可能 | 黒背景HUD、HUDパネル編集、テーマ、MapKit地図・検索・徒歩/車ルート、音声読み上げ、GPS/加速度/ジャイロ/コンパス、バッテリー、人物検出、ローカル保存 |
| B | 条件付きで実現可能 | 外部ディスプレイ独立表示、カメラ背景＋同時HUD出力、Core ML物体認識、音声認識、App Intents、バックグラウンド音声案内、ファイル経由の端末間同期 |
| C | 外部サービス・追加機器が必要 | Google Maps、クラウドAI、天気(Open-Meteo等)、公共交通の詳細経路、Bluetoothセンサー、外部カメラ |
| D | iOSの制約・開発環境により困難 | Swift Playgrounds での CloudKit/WeatherKit/WidgetKit/watchOS、車線検出の実用精度、カメラだけでの正確な距離・衝突予測 |
| E | 現状の環境では実現不可能 | 端末内 Apple Intelligence（A16）、VITUREの頭部トラッキング取得（公開APIなし・未確認）、アプリからのVITURE調光制御、iPhoneでのUSB外部カメラ |

## 3. 推奨する進め方

```
Phase 0  技術スパイク（実機検証 1〜2週）  ← 次にやること（承認後）
Phase 1  HUD基本プロトタイプ（黒背景/カメラ/パネル/外部出力）＝VITURE実機検証
Phase 2  HUDカスタマイズ（テーマ・プリセット・ウィジェット）
Phase 3  MapKitナビゲーション＋音声案内
Phase 4  センサー＋AIビジョン（実験機能）
Phase 5  音声操作＋AIアシスタント
Phase 6  天気・通知・履歴・同期・ショートカット
Phase 7  最適化・iPhone 15 実機検証
```

Phase 0 のスパイクは「捨てる前提の小さな検証コード」であり、本実装（Phase 1〜）とは分けます。

## 4. 承認チェックリスト

承認いただきたい項目：

- [ ] 「ミラーリングでも成立するHUD」を基本設計とし、独立外部画面は検証できた場合に有効化する方針
- [ ] 地図エンジンは **MapKit を主軸**、Google Maps は Phase 3 後半以降の任意対応とする方針
- [ ] AIアシスタントは **ルールベース（無料・端末内）を標準**、クラウドLLMはユーザーがAPIキーを入力した場合のみ有効化する方針
- [ ] 天気は **Open-Meteo（無料・非商用・APIキー不要）** を第一候補とする方針（商用公開する場合は再検討）
- [ ] 端末間同期は Phase 6 まで **JSONエクスポート／インポート（iCloud Drive経由）** で代替する方針
- [ ] 物体認識・危険検知は「実験的な補助機能」として明示し、安全装置として扱わない方針
- [ ] [12_open_questions.md](12_open_questions.md) の質問への回答

## 参照した主な公開情報

- VITURE Pro 2：[B&H](https://www.bhphotovideo.com/c/product/1996511-REG/viture_pfs6001a1a_pro_2_xr_glasses.html) / [Digital Trends](https://www.digitaltrends.com/computing/viture-pro-2-review/) / [The Gadgeteer](https://the-gadgeteer.com/2026/08/06/viture-pro-2-xr-glasses/) / [TechEBlog](https://www.techeblog.com/viture-pro-2-xr-ar-glasses-specs-price-review/) / [Notebookcheck](https://notebookcheck.net/Viture-intros-affordable-Pro-2-XR-glasses-with-lightweight-design-and-bright-displays.1361262.0.html)
- iPad A16：[Apple サポート 技術仕様](https://support.apple.com/en-bh/122240) / [Engadget レビュー（Apple Intelligence非対応）](https://www.engadget.com/mobile/tablets/ipad-2025-with-a16-review-no-apple-intelligence-no-problem-132641539.html) / [Macworld レビュー](https://www.macworld.com/article/2646985/ipad-a16-review.html)
- Swift Playgrounds：[App Store](https://apps.apple.com/lu/app/id908519492) / [Apple Developer: Swift Playgrounds](https://developer.apple.com/swift-playground/) / [WWDC22 Build your first app in Swift Playgrounds](https://developer.apple.com/videos/play/wwdc2022-110348) / [iPadでApp Storeまで開発した事例](https://www.cephalopod.studio/blog/lessons-from-developing-an-app-on-the-ipad-from-start-to-finish-on-the-app-store) / [Developer Forums: CloudKit](https://developer.apple.com/forums/thread/697378)
- Google Maps Platform：[公式 料金ページ](https://developers.google.com/maps/billing-and-pricing/pricing) / [公式 料金概要](https://developers.google.com/maps/billing/overview/)
- Open-Meteo：[公式サイト](https://open-meteo.com/) / [利用規約](https://open-meteo.com/en/terms)
