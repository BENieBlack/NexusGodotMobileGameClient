# NexusGodotMobileGameClient

モバイルゲームのクライアント（Godot 4 / GDScript）。バックエンド API は `NexusLaravelMobileGameServer` が提供する。

このファイルは Claude Code と opencode の両方が毎回読む。ここには毎回守ることだけを書き、詳細は下の「参照資料」に置く。

## 進め方

- 応答・コメント・コミットメッセージ・ドキュメントは日本語。識別子は英語（[.claude/language.md](.claude/language.md)）
- コミットメッセージと PR に AI の共同作者表記（`Co-Authored-By` などの trailer、`Generated with ...` などの署名）を付けない
- main へ直接コミットしない。作業ブランチ（`feature/` `fix/` `docs/` `refactor/` + 英語ケバブケース）を切って PR でマージする
- 設計は Nexus リポジトリ（`docs/requirements/` と `docs/design/`）と、サーバーの `docs/design/<機能>/` が正本。クライアントの設計は `docs/design/<機能>/client_design.md` に置き、仕様を複製しない
- マージ済みの設計と食い違う実装が要るときは、実装で吸収せず設計の修正を先に出す

## 規約（実装前に読む）

| 内容 | 場所 |
| --- | --- |
| 構成・レイヤー（クリーンアーキテクチャ 3 層・コンテキストと共有モジュール master_data・依存ルール・命名・移行方針） | [.claude/architecture.md](.claude/architecture.md) |
| GDScript の規約 | [.claude/coding-standards.md](.claude/coding-standards.md) |
| サーバー API との通信仕様 | [.claude/api.md](.claude/api.md) |
| 画面ごとの設計（クライアント側） | `docs/design/<機能>/client_design.md`（例: [title-to-home](docs/design/title-to-home/client_design.md)） |
| 実装履歴 | [.claude/implementation-history.md](.claude/implementation-history.md) |
| マスターデータ・アセット | [docs/MASTER_DATA.md](docs/MASTER_DATA.md) / [docs/ASSETS.md](docs/ASSETS.md) |

`.opencode` は `.claude` へのシンボリックリンク。ドキュメントやスキルの追加・修正は `.claude/` 側だけで行う。
