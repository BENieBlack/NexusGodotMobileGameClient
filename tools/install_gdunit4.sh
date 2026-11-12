#!/usr/bin/env bash
# GdUnit4（テスト基盤）を、バージョンを固定して addons/gdUnit4 に入れる。
#
# なぜ git に入れないか:
#   ライブラリ本体は約 500 ファイル・3 万行あり、PR の差分を読みにくくする。
#   サードパーティのコードを自分たちのリポジトリで管理する意味も薄いので、
#   版（タグ）と、その版が指すコミットの SHA を固定してダウンロードする方式にしている。
#   addons/gdUnit4/ は .gitignore 済み。
#
# 使い方:
#   bash tools/install_gdunit4.sh          # 未導入なら入れる。入っていて版が同じなら何もしない
#   make setup-gdunit4                     # 同上（Makefile から呼ぶ）。make test は自動で呼ぶ
#
# 版を上げるとき:
#   1. 下の GDUNIT4_TAG と GDUNIT4_SHA を新しい版に直す
#      （SHA は `gh api repos/godot-gdunit-labs/gdUnit4/commits/<タグ> --jq .sha` で得る）
#   2. make setup-gdunit4 && make check で通ることを確かめる（Godot 本体の更新時にも再確認する）
#
# 流れ:
#   1. 入っている版（plugin.cfg の version）が固定の版と同じなら終了
#   2. 一時ディレクトリにタグを浅く clone する（履歴は不要なので --depth 1）
#   3. clone したコミットの SHA が固定の SHA と一致することを確かめる
#      （タグが付け替えられても、改ざんされたコードを取り込まないため）
#   4. addons/gdUnit4 だけを作業ディレクトリへ置き換えて入れる
set -euo pipefail

# --- 固定する版 ---
GDUNIT4_TAG="v6.2.3"
GDUNIT4_SHA="f2e4f8679ebd28e27ef523a4fb7b09e8337bfce9"
GDUNIT4_REPO="https://github.com/godot-gdunit-labs/gdUnit4.git"

# リポジトリのルート（このスクリプトは tools/ にあるので 1 つ上）
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/addons/gdUnit4"

# --- 1. 導入済みで版が同じなら何もしない ---
want_version="${GDUNIT4_TAG#v}"   # 例: v6.2.3 → 6.2.3（plugin.cfg の書式に合わせる）
if [ -f "$DEST/plugin.cfg" ] && grep -q "^version=\"$want_version\"" "$DEST/plugin.cfg"; then
  echo "[gdunit4] 導入済み: $GDUNIT4_TAG"
  exit 0
fi

# --- 2. 固定した版を取得する ---
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT   # 途中で失敗しても一時ディレクトリを残さない
echo "[gdunit4] $GDUNIT4_TAG を取得します"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$GDUNIT4_TAG" "$GDUNIT4_REPO" "$work/src"

# --- 3. コミットの SHA を検証する ---
actual_sha="$(git -C "$work/src" rev-parse HEAD)"
if [ "$actual_sha" != "$GDUNIT4_SHA" ]; then
  echo "[gdunit4] エラー: SHA が一致しません（期待 $GDUNIT4_SHA / 実際 $actual_sha）" >&2
  exit 1
fi

# --- 4. addons/gdUnit4 を置き換える ---
rm -rf "$DEST"
mkdir -p "$ROOT/addons"
cp -R "$work/src/addons/gdUnit4" "$DEST"
echo "[gdunit4] 導入しました: $DEST"
