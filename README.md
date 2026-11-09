# HUD Navigator（仮称）

VITURE XRグラス × iPad A16 / iPhone 15 向け スマートHUDナビゲーションアプリ。

> **現在のステータス：Phase 0（技術調査・計画）— アプリのコードはまだ書いていません。**
> 計画書 §20 の指示に従い、まず調査結果と開発計画を提出しています。
> 内容をご確認・承認いただいた後に Phase 1 の実装を開始します。

## 提出資料（`docs/`）

| # | 資料 | ファイル |
|---|------|----------|
| 0 | エグゼクティブサマリー・承認チェックリスト | [docs/00_summary.md](docs/00_summary.md) |
| 1 | 技術調査レポート | [docs/01_technical_research.md](docs/01_technical_research.md) |
| 2 | 実現可能性一覧（A〜E分類） | [docs/02_feasibility_matrix.md](docs/02_feasibility_matrix.md) |
| 3 | 推奨技術スタック | [docs/03_tech_stack.md](docs/03_tech_stack.md) |
| 4 | アーキテクチャ設計 | [docs/04_architecture.md](docs/04_architecture.md) |
| 5 | ファイル・フォルダ構成 | [docs/05_file_structure.md](docs/05_file_structure.md) |
| 6 | 画面構成図 | [docs/06_screen_map.md](docs/06_screen_map.md) |
| 7 | 機能依存関係図 | [docs/07_dependency_graph.md](docs/07_dependency_graph.md) |
| 8 | 開発ロードマップ | [docs/08_roadmap.md](docs/08_roadmap.md) |
| 9 | テスト計画 | [docs/09_test_plan.md](docs/09_test_plan.md) |
| 10 | 無料・有料サービス一覧 | [docs/10_services_pricing.md](docs/10_services_pricing.md) |
| 11 | リスク・制約一覧 | [docs/11_risks_constraints.md](docs/11_risks_constraints.md) |
| 12 | ユーザーへの確認事項 | [docs/12_open_questions.md](docs/12_open_questions.md) |
| 13 | ビルド・検証パイプライン（GitHub Actions ＋ AltStore） | [docs/13_ci_altstore_pipeline.md](docs/13_ci_altstore_pipeline.md) |

## 開発・検証の流れ

```
このリポジトリ ─▶ GitHub Actions（Linuxテスト → iOSビルド・シミュレータテスト・スナップショット）
               └▶ 未署名 IPA を GitHub Release に添付 ─▶ AltStore で iPad A16 / iPhone 15 にインストール（週7回まで）
```
