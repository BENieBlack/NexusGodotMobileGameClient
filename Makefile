# クライアントの開発コマンド集。使い方は `make help`。
#
# 検査の流れ（make check = CI と同じ。順に実行し、1 つでも失敗したらそこで止まる）:
#   check-deps（依存方向チェックと、その単体テスト）
#     → lint（gdlint）→ format-check（gdformat --check）→ test（GdUnit4）
# *-quiet 系（check-quiet / test-quiet）は同じ検査で、画面には結果だけを出す。全文は .make-logs/ に残る。
#
# 前提:
#   - 初回は `make setup-tools`（lint / format 用の Python 環境 .venv-tools を作り、GdUnit4 を固定した版で addons/ に入れる。
#     GdUnit4 は git に入れていない。make test / import も、無ければ自動で入れる）
#   - Godot は PATH 上の godot。別の場所なら `GODOT_BIN=/path/to/godot make ...`
#   - lint / format-check / format は .venv-tools が無いと失敗する（setup-tools を先に）

.PHONY: help setup-tools setup-gdunit4 check-deps lint format-check format import test test-quiet check check-quiet clean-reports

# Godot 本体。環境変数 GODOT_BIN で上書きできる（GdUnit4 の runtest.sh と同じ変数名）。
# 未指定なら PATH 上の godot を使う。
GODOT_BIN ?= godot
export GODOT_BIN

SHELL := /bin/bash
VENV := .venv-tools
PYTHON ?= python3
# lint / format の対象は新構成のディレクトリだけ（旧構成の scripts/ scenes/ は対象外）。
# $(wildcard ...) は実在するものだけに展開されるので、まだ無いディレクトリ（debug/ など）があっても
# 引数に紛れ込まない。新構成のディレクトリを足したら、ここと tools/check_dependencies.py の
# CHECK_DIRS の両方に足す
SRC_DIRS := $(wildcard app core master_data contexts tests debug)

# *-quiet はエージェント向け。全文は QUIET_LOG_DIR に書き、画面には結果だけを出す
QUIET_LOG_DIR := .make-logs

# 成功なら1行、失敗ならログの末尾を出す（check-quiet が段ごとに使う）
# $(1)=ログ名 $(2)=コマンド $(3)=失敗時に出す末尾の行数（省略時80）
# 流れ: コマンドの全出力を .make-logs/<ログ名>.log に書く → 成功なら "OK <ログ名>" だけ表示
#       → 失敗ならログの末尾と全文の場所を表示し、exit 1 で make を止める（後続の段は実行しない）
define run_quiet
	@mkdir -p $(QUIET_LOG_DIR)
	@if $(2) > $(QUIET_LOG_DIR)/$(1).log 2>&1; then echo "OK $(1)"; \
	else tail -n $(or $(3),80) $(QUIET_LOG_DIR)/$(1).log; echo "NG $(1)（全文: $(QUIET_LOG_DIR)/$(1).log）"; exit 1; fi
endef

# GdUnit4 をヘッドレスで実行するコマンド（test と test-quiet が共有する）。
# 結果は reports/report_1/results.xml（JUnit 形式）。--add res://tests で tests/ 以下の全テストを集める
# -rd reports: レポートの出力先 / -c: 色付き出力（test-quiet は後で色を外す）
# --ignoreHeadlessMode: ヘッドレスでもシーンランナー系のテストを許す
# --remote-debug: スクリプトの構文エラーで対話デバッガに入って止まるのを防ぐ（runtest.sh と同じ）
GDUNIT_RUN = $(GODOT_BIN) --headless --path . -s -d --remote-debug tcp://127.0.0.1:0 \
	res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests -rd reports --ignoreHeadlessMode -c

# 各ターゲットの `## 説明` を拾って一覧にする（make help）
help: ## ヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# GdUnit4 を addons/gdUnit4 に入れる（版と SHA を固定。git には入れていない）。
# 導入済みで版が同じなら何もしない。版の上げ方は tools/install_gdunit4.sh の冒頭を参照
setup-gdunit4: ## GdUnit4（テスト基盤）を固定した版で addons/gdUnit4 に入れる
	bash tools/install_gdunit4.sh

# 依存: Python 3 のみ。.venv-tools が既にあれば再利用し、パッケージを入れ直す（版は requirements.txt で固定）
setup-tools: setup-gdunit4 ## lint / format 用の venv（.venv-tools）と gdtoolkit、GdUnit4 を入れる
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install -q -r tools/requirements.txt

# 順序が大事: 先に単体テストで検査ツール自身が正しいことを確かめ、その上で実リポジトリを検査する
# （ツールが壊れていると「違反なし」が信用できないため）。どちらかが失敗したら make は止まる。
# ルールの一覧は tools/check_dependencies.py の冒頭を参照
check-deps: ## 依存方向チェック（単体テスト → 実リポジトリの検査）
	$(PYTHON) -m unittest discover -s tools/tests
	$(PYTHON) tools/check_dependencies.py

# 前提: setup-tools 済み。設定は .gdlintrc。違反があると終了コード 1
lint: ## gdlint（新構成のディレクトリ）
	$(VENV)/bin/gdlint $(SRC_DIRS)

# 前提: setup-tools 済み。整形が必要なファイルがあると失敗する（CI 用。直すには make format）
format-check: ## gdformat --check（書き換えない）
	$(VENV)/bin/gdformat --check $(SRC_DIRS)

# 前提: setup-tools 済み。ファイルを書き換える。コミット前に実行する
format: ## gdformat で整形する
	$(VENV)/bin/gdformat $(SRC_DIRS)

# 初回やアドオン追加の後は、先に import が要る（class_name のキャッシュを作る）。
# キャッシュが無いと、テストが class_name を解決できず失敗することがある
import: setup-gdunit4 ## Godot のインポートを実行（ヘッドレス。GdUnit4 が無ければ先に入れる）
	$(GODOT_BIN) --headless --path . --import

# GdUnit4 は reports/report_N を増やしていくので、実行のたびに消して作り直す（古い結果と混ざらないように）。
# 内部用で、test / test-quiet から依存として呼ばれる
clean-reports:
	rm -rf reports

# 依存の順序: import → clean-reports → テスト本体。失敗するテストがあれば Godot の終了コードで make が失敗する
test: import clean-reports ## GdUnit4 の全テスト（ヘッドレス）
	$(GDUNIT_RUN)

# 失敗したときは、ログの末尾（失敗したテストと集計）を出す。ANSI の色は外す。
# 流れ:
#   1. import（結果は無視。|| true）。失敗してもテスト本体の結果で判定するため
#   2. GdUnit4 を実行し、生ログを test.raw に残す。終了コードは status に取っておく
#   3. 生ログから ANSI のエスケープ（色）を除いて test.log にする（grep・tail で読みやすくするため）
#   4. status が 0 で、かつ "Overall Summary"（GdUnit4 の最終集計行）がログにあれば成功。
#      集計行まで確認するのは、起動に失敗して何も実行されなかったときを成功と取り違えないため
#   5. それ以外はログの末尾を出して exit 1（シェル変数の $ を 2 つ重ねるのは、make に展開させないため）
test-quiet: setup-gdunit4 clean-reports ## GdUnit4 の全テスト。結果だけ表示（エージェント向け）
	@mkdir -p $(QUIET_LOG_DIR)
	@$(GODOT_BIN) --headless --path . --import > $(QUIET_LOG_DIR)/import.log 2>&1 || true
	@$(GDUNIT_RUN) > $(QUIET_LOG_DIR)/test.raw 2>&1; status=$$?; \
	sed $$'s/\x1b\\[[0-9;]*[A-Za-z]//g' $(QUIET_LOG_DIR)/test.raw > $(QUIET_LOG_DIR)/test.log; \
	if [ $$status -eq 0 ] && grep -q 'Overall Summary' $(QUIET_LOG_DIR)/test.log; then \
		grep -E 'Overall Summary' $(QUIET_LOG_DIR)/test.log; echo "全文: $(QUIET_LOG_DIR)/test.log"; \
	else tail -n 80 $(QUIET_LOG_DIR)/test.log; echo "NG test（終了コード $${status}。全文: $(QUIET_LOG_DIR)/test.log）"; exit 1; fi

# CI と同じ検査をローカルで回す。依存の並び順がそのまま実行順（make は左から順に実行し、失敗で止まる）
check: check-deps lint format-check test ## CI と同じ検査（依存方向 → lint → format → テスト）

# 実行順は check と同じ。各段のログは .make-logs/<段>.log。どの段で落ちたかは "NG <段>" で分かる
check-quiet: ## check と同じ検査。結果だけを表示（エージェント向け）
	$(call run_quiet,check-deps-test,$(PYTHON) -m unittest discover -s tools/tests)
	$(call run_quiet,check-deps,$(PYTHON) tools/check_dependencies.py)
	$(call run_quiet,lint,$(VENV)/bin/gdlint $(SRC_DIRS))
	$(call run_quiet,format-check,$(VENV)/bin/gdformat --check $(SRC_DIRS))
	@$(MAKE) --no-print-directory test-quiet
