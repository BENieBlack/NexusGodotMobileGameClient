#!/usr/bin/env python3
"""製品ビルド用に、開発専用のものを除いたプロジェクトの複製を作る。

なぜ複製か:
  E2EDriver（debug/）は project.godot の [autoload] に登録してある。製品ビルドで debug/ だけを
  除外して autoload の行を残すと、起動時にオートロードのロードエラーになる。Godot 4.7 は autoload の
  キーに機能タグ（debug など）を付けても条件付きにしてくれない（すべての場合に読み込まれる）ので、
  「除外して、この 1 行も外す」を人の手順にせず、複製を作る段階で機械的に行う。
  元の project.godot は変えない（開発では E2EDriver が要るため）。

許可リスト方式を選んだ理由:
  除外リスト方式（「開発用のものを除く」）だと、新しい開発用ファイルの足し忘れが製品に混ざる。
  これは誰も気付かない「見えない失敗」になる。許可リスト方式は「迷ったら含めない」になり、
  足し忘れ（含めるべきものを INCLUDE に書き忘れた）は起動検査で壊れて見える。さらに、リポジトリの
  トップレベルとアドオンの全エントリを INCLUDE / EXCLUDE の明示的な 2 リストに分類させ、
  どちらにも無い名前（未分類）があれば失敗にする。足し忘れを「見える失敗」にするための仕組み。

流れ:
  1. 出力先の保護を検査する
  2. 未分類のトップレベル・アドオンが無いか調べる（あれば名前を列挙して終了コード 1。何も消さない）
  3. 出力先を作り直し、INCLUDE のものだけを複製する（アドオンは ADDONS_INCLUDE だけ）
  4. 複製の project.godot から、除外したものを指す autoload と editor_plugins を外す
  5. ガード: 複製の中に、除外したものへの参照、または複製に実在しない res:// の参照が無いか調べる
     （あれば終了コード 1）

使い方: python3 tools/prepare_release_project.py [--root .] --out build/release-project [--force]
終了コード: 0 = 成功 / 1 = 未分類の検出、またはガードが参照を検出 / 2 = 引数・出力先の誤り（何も消さない）
Python 3.9 互換・標準ライブラリのみ。
"""
import argparse
import os
import re
import shutil
import subprocess
import sys

# --- トップレベルの分類（INCLUDE と EXCLUDE の 2 つ。どちらにも無い名前は未分類として失敗にする） ---
# 新しいトップレベルのディレクトリ・ファイルを足したら、どちらかに書く。

# 製品に含めるもの（ゲームの実行に要るもの）
INCLUDE = [
    "project.godot",  # プロジェクト設定（複製では変換する）
    "icon.svg",  # アプリのアイコン（config/icon が参照する）
    "icon.svg.import",  # アイコンのインポート設定
    "app",  # AppContext・SceneRouter（オートロードの実体）
    "core",  # 共通の基盤
    "contexts",  # 機能ごとのコンテキスト（シーン・スクリプト）
    "master_data",  # マスターデータの取り込み
    "data",  # データ（マスターの DB など）
    "assets",  # フォント・UI 画像
    "addons",  # 実行に要るアドオン（中身は ADDONS_INCLUDE / ADDONS_EXCLUDE で分類）
    "export_presets.cfg",  # 書き出しプリセット（元にあれば複製にも入れる。無ければ複製の中に置く）
]

# 製品に含めないもの（理由つき）
EXCLUDE = [
    ".git",  # バージョン管理
    ".godot",  # エディタのキャッシュ（複製側で import が作り直す）
    ".gitignore",  # バージョン管理の設定
    ".gitattributes",  # バージョン管理の設定
    ".editorconfig",  # エディタの設定
    ".gdlintrc",  # lint の設定（開発用）
    ".claude",  # AI エージェントの設定・規約
    ".opencode",  # AI エージェントの設定
    ".github",  # CI の設定
    "opencode.json",  # AI エージェントの設定
    "CLAUDE.md",  # 開発の案内
    "Makefile",  # 開発コマンド
    "LICENSE",  # リポジトリのライセンス表記（製品側の表記は別途用意する）
    "docs",  # 設計・手順の文書
    "debug",  # 開発専用（E2EDriver・検証スクリプト）
    "tests",  # テスト
    "tools",  # 開発用ツール（この複製の生成を含む）
    "reports",  # テストの出力
    "build",  # この複製の出力先
    ".make-logs",  # make の検査ログ
    ".venv-tools",  # lint 用の Python 環境
]

# addons/ 直下の分類。ここも未分類があれば失敗にする（実在のディレクトリが対象。git 管理外で入るものも含む）
ADDONS_INCLUDE = ["godot-sqlite"]  # SQLite（マスターデータの読み込みに要る）
ADDONS_EXCLUDE = ["gdUnit4"]  # テスト基盤。実行には要らない（git に入れず make setup-tools で入る）

# 複製の中に残ってはいけない参照（これらのパスはガードで検出する。製品コードが開発専用のものに依存している誤り）
FORBIDDEN_REFS = ["res://debug/", "res://tests/", "res://addons/gdUnit4"]

# autoload のスクリプトがこの接頭辞で始まるエントリは、複製の project.godot から削除する（E2EDriver など）
EXCLUDED_AUTOLOAD_PREFIXES = ["res://debug/", "res://tests/", "res://addons/gdUnit4/"]

# editor_plugins の enabled から外すプラグイン（plugin.cfg のパスの接頭辞。godot-sqlite は残す）
EXCLUDED_PLUGIN_PREFIXES = ["res://addons/gdUnit4/"]

# 無視するファイル名（OS・Python のゴミ。分類の対象にせず、複製もしない）
IGNORE_NAMES = {".DS_Store", "__pycache__"}

# ガードで読む拡張子（project.godot は名前で判定）
GUARD_EXTENSIONS = (".gd", ".tscn", ".tres")

# 出力先として --force なしで消してよい場所（root からの相対）
SAFE_OUT_DIR = "build"


class UsageError(Exception):
    """引数・出力先の誤り。終了コード 2 にする。"""


def check_out_dir(root, out, force):
    """出力先を消してよいか検査する。危険なら UsageError（何も消さない）。

    守るもの: ルート（/）・ホーム・リポジトリのルート・その親（祖先）・複製元として使うトップのものを
    消さない。--force でも同じ。build/ 配下以外は、--force が無ければ拒否する。
    """
    root = os.path.realpath(root)
    out = os.path.realpath(out)
    if out == os.path.dirname(out):
        raise UsageError("出力先がファイルシステムのルートです: " + out)
    if out == os.path.realpath(os.path.expanduser("~")):
        raise UsageError("出力先がホームディレクトリです: " + out)
    # 出力先が root と同じ、または root を含む（祖先）なら、リポジトリごと消してしまう
    if out == root or root.startswith(out + os.sep):
        raise UsageError("出力先がリポジトリのルート（またはその祖先）です: " + out)
    # 出力先が複製元（INCLUDE のもの）と同じ、またはその中だと、元を消す・自分自身を複製してしまう
    for name in INCLUDE:
        source = os.path.join(root, name)
        if out == source or out.startswith(source + os.sep):
            raise UsageError("出力先が複製元の中です: " + out)
    safe = os.path.join(root, SAFE_OUT_DIR) + os.sep
    if not (out + os.sep).startswith(safe) and not force:
        raise UsageError(
            "出力先が %s/ 配下ではありません（消してよいなら --force）: %s" % (SAFE_OUT_DIR, out)
        )
    return out


def top_level_entries(root):
    """リポジトリのルート直下のエントリ名を返す。

    git 管理下なら `git ls-files` の最上位（管理されているものだけ。個人の未追跡ファイルや
    エディタ・OS のゴミで失敗しないため）。git が無い・使えないときは os.listdir（IGNORE_NAMES を除く）。
    """
    if os.path.isdir(os.path.join(root, ".git")):
        try:
            result = subprocess.run(
                ["git", "-C", root, "ls-files", "-z"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                check=True,
            )
            names = {p.split(b"/")[0].decode("utf-8") for p in result.stdout.split(b"\0") if p}
            return sorted(names - IGNORE_NAMES)
        except (OSError, subprocess.CalledProcessError):
            pass  # git が使えない: listdir に回る
    return sorted(set(os.listdir(root)) - IGNORE_NAMES)


def find_unclassified(root):
    """INCLUDE / EXCLUDE に無いトップレベルと、ADDONS_* に無いアドオンの名前を返す。

    戻り値: (未分類のトップレベル, 未分類のアドオン)。アドオンは実在のディレクトリだけが対象
    （addons/README.md のようなファイルは見ない）。
    """
    known = set(INCLUDE) | set(EXCLUDE)
    top = [n for n in top_level_entries(root) if n not in known]
    addons = []
    addons_dir = os.path.join(root, "addons")
    if os.path.isdir(addons_dir):
        known_addons = set(ADDONS_INCLUDE) | set(ADDONS_EXCLUDE)
        for name in sorted(os.listdir(addons_dir)):
            if name in IGNORE_NAMES or not os.path.isdir(os.path.join(addons_dir, name)):
                continue
            if name not in known_addons:
                addons.append(name)
    return top, addons


def copy_project(root, out):
    """INCLUDE のものを out に複製し、コピーしたファイル数を返す。addons/ は ADDONS_INCLUDE だけ。"""
    root = os.path.realpath(root)
    os.makedirs(out)
    skip = shutil.ignore_patterns(*sorted(IGNORE_NAMES), "*.pyc")
    for name in INCLUDE:
        source = os.path.join(root, name)
        target = os.path.join(out, name)
        if name == "addons":
            os.makedirs(target, exist_ok=True)
            for addon in ADDONS_INCLUDE:
                if os.path.isdir(os.path.join(source, addon)):
                    shutil.copytree(os.path.join(source, addon), os.path.join(target, addon), ignore=skip)
        elif os.path.isdir(source):
            shutil.copytree(source, target, ignore=skip)
        elif os.path.isfile(source):
            shutil.copy2(source, target)
        # data/ や export_presets.cfg は無いことがある
    count = 0
    for _dir, _dirs, files in os.walk(out):
        count += len(files)
    return count


def _autoload_script(line):
    """autoload の行（例: `E2EDriver="*res://debug/e2e_driver.gd"`）から res:// のパスを取り出す。無ければ None。

    先頭の `*` は「シングルトンとして有効」の印なので落とす。
    """
    match = re.match(r'^\s*[A-Za-z_][A-Za-z0-9_]*\s*=\s*"\*?(res://[^"]*)"', line)
    return match.group(1) if match else None


def transform_project_godot(text):
    """project.godot の本文を製品用に変換する。(新しい本文, 削除した autoload 名, 外したプラグイン) を返す。

    変換:
      - [autoload]: スクリプトが除外ディレクトリ（debug/・tests/・gdUnit4）にあるエントリを行ごと削除
        （残すとオートロードのロードエラーになる）。他のエントリと順序は変えない。
      - [editor_plugins] の enabled: 除外したアドオンの plugin.cfg を外す。複製に gdUnit4 が無いので、
        残すとプラグインの読み込み失敗になる。godot-sqlite など他のプラグインは残す。
    """
    section = ""
    removed_autoloads = []
    removed_plugins = []
    out_lines = []
    for line in text.splitlines(keepends=True):
        header = re.match(r"^\s*\[([^\]]+)\]", line)
        if header:
            section = header.group(1)
        elif section == "autoload":
            script = _autoload_script(line)
            if script and any(script.startswith(p) for p in EXCLUDED_AUTOLOAD_PREFIXES):
                removed_autoloads.append(line.split("=")[0].strip())
                continue
        elif section == "editor_plugins" and re.match(r"^\s*enabled\s*=", line):
            kept = []
            for path in re.findall(r'"([^"]*)"', line):
                if any(path.startswith(p) for p in EXCLUDED_PLUGIN_PREFIXES):
                    removed_plugins.append(path)
                else:
                    kept.append(path)
            newline = "\n" if line.endswith("\n") else ""
            line = "enabled=PackedStringArray(%s)%s" % (
                ", ".join('"%s"' % p for p in kept),
                newline,
            )
        out_lines.append(line)
    return "".join(out_lines), removed_autoloads, removed_plugins


# res:// のパスを取り出す正規表現。引用符・空白・括弧・カンマ・`]` までをパスとする
# 例: `preload("res://core/toast.gd")` → core/toast.gd /  `path="res://assets/ui/a.png"` → assets/ui/a.png
RES_PATH_RE = re.compile(r"res://([^\"'\s)\],]*)")


def _is_comment(name, line):
    """コメント行か。project.godot は `;`、.gd は `#` で始まる行（説明文なので参照として見ない）。"""
    stripped = line.lstrip()
    if name == "project.godot":
        return stripped.startswith(";")
    if name.endswith(".gd"):
        return stripped.startswith("#")
    return False


def find_bad_refs(out):
    """複製に残った問題のある参照を [(相対パス, 行番号, 行, 理由)] で返す。

    最終防衛線として 2 種類を調べる:
      - 除外したもの（FORBIDDEN_REFS）への参照: 製品コードが debug/ や tests/ に依存している誤り
      - 複製に実在しない res:// の参照: INCLUDE への入れ忘れ（書き出す前に検出する）
    対象外: コメント行、`.godot` 配下（インポートの生成物）、動的に組み立てる文字列
    （`%` `{` `*` を含む。例: "res://assets/%s.png" % name）、末尾が `/` のディレクトリ接頭辞は
    ディレクトリの実在だけ見る。
    """
    found = []
    for directory, _dirs, files in os.walk(out):
        # 生成物（.godot）は見ない
        if os.path.relpath(directory, out).split(os.sep)[0] == ".godot":
            continue
        for name in sorted(files):
            if not (name.endswith(GUARD_EXTENSIONS) or name == "project.godot"):
                continue
            path = os.path.join(directory, name)
            rel = os.path.relpath(path, out)
            with open(path, encoding="utf-8", errors="replace") as f:
                for number, line in enumerate(f, 1):
                    if _is_comment(name, line):
                        continue
                    if any(ref in line for ref in FORBIDDEN_REFS):
                        found.append((rel, number, line.rstrip(), "除外したものへの参照"))
                        continue  # 実在チェックと二重に出さない
                    for ref in RES_PATH_RE.findall(line):
                        if not ref or any(c in ref for c in "%{*"):
                            continue
                        if ref.split("/")[0] == ".godot":
                            continue
                        if not os.path.exists(os.path.join(out, ref)):
                            found.append((rel, number, line.rstrip(), "複製に無い res://" + ref + " への参照"))
    return found


def prepare(root, out, force=False):
    """複製を作って変換・検査する。終了コードを返す。"""
    out = check_out_dir(root, out, force)

    # 未分類があれば、何も消さずに失敗する（足し忘れを必ず気付かせる）
    unclassified_top, unclassified_addons = find_unclassified(os.path.realpath(root))
    if unclassified_top or unclassified_addons:
        print("NG: 製品に含めるか除外するか未分類のものがあります:")
        for name in unclassified_top:
            print("  トップレベル: " + name)
        for name in unclassified_addons:
            print("  addons/" + name)
        print(
            "製品に含めるか除外するかを tools/prepare_release_project.py の INCLUDE / EXCLUDE"
            "（アドオンは ADDONS_INCLUDE / ADDONS_EXCLUDE）に追加してください"
        )
        return 1

    if os.path.lexists(out):
        shutil.rmtree(out)
    count = copy_project(root, out)

    godot_path = os.path.join(out, "project.godot")
    with open(godot_path, encoding="utf-8") as f:
        text = f.read()
    new_text, autoloads, plugins = transform_project_godot(text)
    with open(godot_path, "w", encoding="utf-8") as f:
        f.write(new_text)

    print("製品用の複製を作りました: " + out)
    print("コピーしたファイル数: %d" % count)
    print("削除した autoload: " + (", ".join(autoloads) or "なし"))
    print("外したプラグイン: " + (", ".join(plugins) or "なし"))

    found = find_bad_refs(out)
    if found:
        print("NG: 複製に、問題のある参照が残っています:")
        for rel, number, line, reason in found:
            print("  %s:%d: [%s] %s" % (rel, number, reason, line))
        return 1
    print("OK: 未分類・除外したものへの参照・複製に無い参照はありません")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="製品ビルド用のプロジェクトの複製を作る")
    parser.add_argument("--root", default=".", help="元のプロジェクト（既定: .）")
    parser.add_argument("--out", required=True, help="出力先（例: build/release-project）")
    parser.add_argument("--force", action="store_true", help="build/ 配下以外の出力先を消して作り直す")
    args = parser.parse_args(argv)
    try:
        return prepare(args.root, args.out, args.force)
    except UsageError as e:
        print("エラー: " + str(e), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
