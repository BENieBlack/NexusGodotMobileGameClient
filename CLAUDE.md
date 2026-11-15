# NexusMobileGameClient-Godot

モバイルゲームのクライアント（Godot 4 / GDScript）。バックエンド API は `NexusLaravelMobileGameServer` が提供する。

このファイルは Claude Code と opencode の両方が毎回読む。ここには毎回守ることだけを書き、詳細は下の「参照資料」に置く。

## 進め方

- 応答・コメント・コミットメッセージ・ドキュメントは日本語。識別子は英語（[.claude/language.md](.claude/language.md)）
- コードには処理の流れと理由が分かるコメントを書く（[coding-standards.md](.claude/coding-standards.md) のコメントの節）
- コミットメッセージと PR に AI の共同作者表記（`Co-Authored-By` などの trailer、`Generated with ...` などの署名）を付けない
- 個人情報（個人名・個人や会社のメール・会社名・ホーム配下の絶対パス・トークン）をコミット・PR・文書・コードに入れない。コミット前に `bash scripts/check-private-info.sh`（追跡ファイル全体は `--all`。CI の「個人情報の検査」も同じ）。個人名・会社名はローカルの `.private-denylist`（git に入れない）にだけ書く。規則は Nexus の `docs/workflow/private-info.md`
- main へ直接コミットしない。作業ブランチ（`feature/` `fix/` `docs/` `refactor/` + 英語ケバブケース）を切って PR でマージする
- 設計は Nexus リポジトリ（`docs/requirements/` と `docs/design/`）と、サーバーの `docs/design/<機能>/` が正本。クライアントの設計は `docs/design/<機能>/client_design.md` に置き、仕様を複製しない
- マージ済みの設計と食い違う実装が要るときは、実装で吸収せず設計の修正を先に出す
- 仕上げに `make check-quiet`（依存方向 → lint → format → テスト）を通す。実装中は関係するテストだけ回す。全文のログは `.make-logs/` を必要な部分だけ読む
- 接続先は `ApiConfig`（`core/data/config/`）の 1 か所で、環境変数 → `project.godot` の `[nexus]` → 既定値の順に決まる: `NEXUS_API_BASE_URL` / `NEXUS_MASTER_BASE_URL`、Reverb は `NEXUS_REVERB_HOST` / `_PORT` / `_SCHEME` / `_APP_KEY`（`[nexus]` は `api_base_url` `master_base_url` `reverb_host` `reverb_port` `reverb_scheme` `reverb_app_key`）。`X-Platform` の値は `NEXUS_PLATFORM` → `[nexus]` の `platform` → OS の既定（iOS → Apple、Android → Google、それ以外 → Apple。許可値は `Apple` / `Google`）。言語は `ApiConfig.language()` の固定 `ja`（上書きなし。全 `request()` に `Accept-Language: ja` を付け、`mst_item` の名前の引きにも使う）。Reverb のアプリキーの既定値は `nexus-local-key`（ローカル開発用。製品・他環境では `NEXUS_REVERB_APP_KEY` か `[nexus]` で上書き）。URL を直書きしない（[api.md](.claude/api.md)）

## コマンド（初回は `make setup-tools`。Godot は PATH 上の `godot`、別の場所なら `GODOT_BIN=/path/to/godot make ...`）

| 用途 | コマンド |
| --- | --- |
| CI と同じ検査 | `make check`（結果だけ: `make check-quiet`） |
| 依存方向チェック | `make check-deps`（`tools/check_dependencies.py` とその単体テスト） |
| 初回の準備（GdUnit4 と lint 用の Python 環境） | `make setup-tools`（GdUnit4 は git に入れず、`tools/install_gdunit4.sh` が版と SHA を固定して `addons/gdUnit4/` に入れる） |
| テスト（GdUnit4、ヘッドレス） | `make test`（結果だけ: `make test-quiet`）。結果の XML は `reports/` |
| lint / 整形 | `make lint` / `make format-check` / `make format`（新構成のディレクトリだけ） |
| 製品ビルド用の複製（debug/・tests/・gdUnit4 と E2EDriver の autoload を除く） | `make release-project`（出力: `build/release-project`）。複製の起動検査は `make check-release`（結果だけ: `make check-release-quiet`。`make check` に含む） |
| 一部だけ | `GODOT_BIN=godot` を付けて `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/unit/xxx_test.gd --ignoreHeadlessMode` |

## 製品ビルド（書き出し）の手順

1. `make release-project` で `build/release-project` を作る（開発専用のものと E2EDriver の autoload を除いた複製。元のリポジトリは変えない）
2. 生成された `build/release-project` を Godot で開き、そこで書き出す。`export_presets.cfg` は複製の中に置く（元のリポジトリに置いてあれば、複製に自動でコピーされる）
3. 書き出しテンプレートと export_presets.cfg は別途用意が要る（リポジトリには無い）

新しいトップレベルのディレクトリ・ファイル・アドオンを足したら、`tools/prepare_release_project.py` の `INCLUDE` / `EXCLUDE`（アドオンは `ADDONS_INCLUDE` / `ADDONS_EXCLUDE`）に分類する。忘れると `make check-release`（CI）が失敗する。製品コードが複製に無いもの（`INCLUDE` に無いディレクトリなど）を `res://` で参照している場合も同じく失敗する。

未確認: 実際の書き出し（テンプレートと presets が手元に無いため）。確かめたのは、複製のヘッドレス起動（`make check-release`）まで。

## 規約（実装前に読む）

| 内容 | 場所 |
| --- | --- |
| 構成・レイヤー（クリーンアーキテクチャ 3 層・コンテキストと共有モジュール master_data・依存ルール・命名・移行方針） | [.claude/architecture.md](.claude/architecture.md) |
| GDScript の規約 | [.claude/coding-standards.md](.claude/coding-standards.md) |
| コメントの規約（ファイル冒頭・関数・処理の見出し・why・テスト・設定ファイル） | [.claude/coding-standards.md](.claude/coding-standards.md) の「コメント」の節 |
| サーバー API との通信仕様 | [.claude/api.md](.claude/api.md) |
| 画面ごとの設計（クライアント側） | `docs/design/<機能>/client_design.md`（例: [title-to-home](docs/design/title-to-home/client_design.md)） |
| 実装履歴 | [.claude/implementation-history.md](.claude/implementation-history.md) |
| マスターデータ・アセット | [docs/MASTER_DATA.md](docs/MASTER_DATA.md) / [docs/ASSETS.md](docs/ASSETS.md) |

`.opencode` は `.claude` へのシンボリックリンク。ドキュメントやスキルの追加・修正は `.claude/` 側だけで行う。
