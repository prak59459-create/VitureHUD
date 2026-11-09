# 00. エグゼクティブサマリー

調査日：2026-11-09
対象計画書：「VITURE対応 AIスマートHUDナビゲーションアプリ 開発計画書」

> **改訂（2026-11-09）**：ユーザー指示「検証は AltStore を使うが週7回程度なので、大半は GitHub Actions で済ませる」を反映。
> ビルドとテストの中心を **GitHub Actions** に移し、実機インストールは **AltStore** で行う。詳細は [13_ci_altstore_pipeline.md](13_ci_altstore_pipeline.md)。

本資料群の記述ルール：
- **【確認済】** … 公式情報・複数の公開情報で確認できたもの
- **【要実機検証】** … 仕様上は可能と考えられるが、本プロジェクトの環境（VITURE実機・AltStore）で動くか未確認のもの
- **【未確認】** … 公開情報で確認できなかったもの。実現可能と断言しない

---

## 1. 結論（先に要点）

1. **HUDの中核（黒背景HUD・カメラ背景・自由配置パネル・MapKitナビ・センサー・音声案内）は、通常のiOS APIで実現可能（A〜B）。** 無料で作れる範囲が大きい。
2. **開発の進め方は3つの検証ループ**（[13](13_ci_altstore_pipeline.md) §0）：
   - **Swift Playgrounds（iPad・回数無制限）**：VITURE・カメラ・センサー・MapKit・音声など iPad で動くものは、まずここでたくさん試す。
   - **GitHub Actions（自動・無制限）**：ロジックテスト、iOS ビルド、見た目のスナップショット。リポジトリは公開なので macOS ランナーも無料。
   - **AltStore IPA（週7回まで）**：iPhone 15 での動作と、正式アプリでしか動かない機能（外部ディスプレイの独立表示、ショートカット、バックグラウンド）を確認。
   - ソースは1か所で、Swift Playgrounds 用 `.swiftpm` と CI 用の両方からビルドする（二重管理しない）。
   - **iPhone 15 にも AltStore でインストールできる**ため、有料 Apple Developer Program や Mac は必須ではない。Windows PC は AltServer（署名更新）や編集に使える。
3. **IPA の実機検証は週7回までに抑える。** iPad で試せることは Playgrounds、ロジックと見た目は CI で済ませ、IPA は「iPhone 15」と「正式アプリ限定の機能」の確認に使う。
4. **外部ディスプレイの独立表示（端末＝操作、グラス＝HUD）は、通常アプリとしてインストールすれば動く可能性が高い**【要実機検証】。念のため「ミラーリングでも成立するHUD設計」は維持する（黒背景＝透明なので黒帯も問題にならない）。
5. **端末内の生成AI（Apple Foundation Models / Apple Intelligence）は iPad A16・iPhone 15 のどちらでも使えない**【確認済】。AIアシスタントは「端末内ルールベース音声コマンド（無料）」＋「任意のクラウドLLM（ユーザーのAPIキー）」の二段構成。
6. **VITURE Pro 2 は実在する製品**【確認済：2026年8月発表、1920×1080/片目 Micro-OLED、最大1600nit、カメラなし、約63g】。iOS アプリから頭部トラッキング値を取得する公開APIは確認できない【未確認】。
7. **無料 Apple ID ＋ AltStore の制約**：署名は7日で失効、同時インストール数・App ID 登録数に上限 → **アプリは1本・App Extension なし**で設計する。CloudKit・WeatherKit など有料アカウント限定の機能は引き続き代替手段で対応。
8. 「Swift Playgrounds 6」は公開情報で確認できなかった（最新確認版は 4.7）。どの版でも動くよう、Playgrounds 側では特殊な機能を使わない（正式ビルド限定の機能は `FULL_BUILD` で切り分け）。

## 2. 分類の集計（詳細は [02_feasibility_matrix.md](02_feasibility_matrix.md)）

| 分類 | 意味 | 主な機能 |
|------|------|----------|
| A | 通常のiOSアプリで実現可能 | 黒背景HUD、HUDパネル編集、テーマ、MapKit地図・検索・徒歩/車ルート、音声読み上げ、GPS/加速度/ジャイロ/コンパス、バッテリー、人物検出、ローカル保存 |
| B | 条件付きで実現可能 | 外部ディスプレイ独立表示、カメラ背景＋同時HUD出力、Core ML物体認識、音声認識、App Intents、バックグラウンド音声案内、ファイル経由の端末間同期 |
| C | 外部サービス・追加機器が必要 | Google Maps、クラウドAI、天気(Open-Meteo等)、公共交通の詳細経路、Bluetoothセンサー、外部カメラ |
| D | iOSの制約・アカウントの制約により困難 | CloudKit/WeatherKit（無料アカウント不可）、ホーム画面ウィジェット（App ID 消費）、watchOS、車線検出の実用精度、カメラだけでの正確な距離・衝突予測 |
| E | 現状の環境では実現不可能 | 端末内 Apple Intelligence（A16）、VITUREの頭部トラッキング取得（公開APIなし・未確認）、アプリからのVITURE調光制御、iPhoneでのUSB外部カメラ |

## 3. 推奨する進め方

```
Phase 0  CIパイプライン構築＋技術スパイク  ← 次にやること（承認後）
         S0-0: GitHub Actions で未署名IPA → AltStore でインストールできるか
Phase 1  HUD基本プロトタイプ（黒背景/カメラ/パネル/外部出力）＝VITURE実機検証
Phase 2  HUDカスタマイズ（テーマ・プリセット・ウィジェット）
Phase 3  MapKitナビゲーション＋音声案内
Phase 4  センサー＋AIビジョン（実験機能）
Phase 5  音声操作＋AIアシスタント
Phase 6  天気・通知・履歴・同期・ショートカット
Phase 7  最適化・iPhone 15 実機検証
```

## 4. 承認チェックリスト

- [ ] **ビルド・テストは GitHub Actions、実機は AltStore（週7回まで）** とする方針（[13](13_ci_altstore_pipeline.md)）
- [ ] ソースは `HUDNavigator.swiftpm/` の1か所に置き、Swift Playgrounds・Linux テスト・XcodeGen（CI）の3つから参照する構成とする方針（[05](05_file_structure.md)）
- [ ] 「ミラーリングでも成立するHUD」を維持し、独立外部画面は実機で確認できたら既定にする方針
- [ ] 地図エンジンは **MapKit を主軸**、Google Maps は任意対応とする方針
- [ ] AIアシスタントは **ルールベース（無料・端末内）を標準**、クラウドLLMはユーザーがAPIキーを入力した場合のみ有効化する方針
- [ ] 天気は **Open-Meteo（無料・非商用・APIキー不要）** を第一候補とする方針
- [ ] 端末間同期は **JSONエクスポート／インポート（iCloud Drive経由）** で代替する方針
- [ ] 物体認識・危険検知は「実験的な補助機能」として明示し、安全装置として扱わない方針
- [ ] [12_open_questions.md](12_open_questions.md) の質問への回答

## 参照した主な公開情報

- VITURE Pro 2：[B&H](https://www.bhphotovideo.com/c/product/1996511-REG/viture_pfs6001a1a_pro_2_xr_glasses.html) / [Digital Trends](https://www.digitaltrends.com/computing/viture-pro-2-review/) / [The Gadgeteer](https://the-gadgeteer.com/2026/08/06/viture-pro-2-xr-glasses/) / [TechEBlog](https://www.techeblog.com/viture-pro-2-xr-ar-glasses-specs-price-review/) / [Notebookcheck](https://notebookcheck.net/Viture-intros-affordable-Pro-2-XR-glasses-with-lightweight-design-and-bright-displays.1361262.0.html)
- iPad A16：[Apple サポート 技術仕様](https://support.apple.com/en-bh/122240) / [Engadget レビュー（Apple Intelligence非対応）](https://www.engadget.com/mobile/tablets/ipad-2025-with-a16-review-no-apple-intelligence-no-problem-132641539.html) / [Macworld レビュー](https://www.macworld.com/article/2646985/ipad-a16-review.html)
- Swift Playgrounds：[App Store](https://apps.apple.com/lu/app/id908519492) / [Apple Developer: Swift Playgrounds](https://developer.apple.com/swift-playground/)
- GitHub Actions：[macOS 26 ランナー一般提供](https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/)
- AltStore：[AltServer リリースノート](https://faq.altstore.io/release-notes/altserver) / [AltStore FAQ](https://faq.altstore.io/altstore-world/your-altstore)
- Google Maps Platform：[公式 料金ページ](https://developers.google.com/maps/billing-and-pricing/pricing)
- Open-Meteo：[公式サイト](https://open-meteo.com/) / [利用規約](https://open-meteo.com/en/terms)
