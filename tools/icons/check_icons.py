#!/usr/bin/env python3
"""アイコン（SVG）の検査（make check-icons。make check に含む）。

目的: アイコンが規格（要件 I2・I3・I8、client_design.md 5-1）を守り、生成スクリプトの出力と
      リポジトリの中身が食い違っていないことを機械的に確かめる。手で SVG を直した・足し忘れた・
      生成し直し忘れた、を見える失敗にする。

検査（problems として列挙。1 件でもあれば終了コード 1）:
  1. 規格: 各 SVG が viewBox 128×128・width/height 128・サイズ上限以内・禁止要素なし・
           線の太さ 4〜10・図形が余白 8 の内側・背景の全面塗りなし
  2. 生成との一致: generate_icons.expected_files() の内容と、リポジトリのファイル（SVG・item_icon_table.gd）が完全一致
           （= 生成して差分が出ない。git ではなくファイルの内容で比べるので、未コミットでも検査できる）
  3. 表と実在: assets/icons/ にある SVG が、表（ITEMS・カテゴリ・unknown・stamp）の全てと一致する
           （表に無い SVG・SVG の無い表の行を検出）。item_icon_table.gd の preload の先が実在する
  4. 定義の整合: ITEMS の全行に SPECS がある・カテゴリごとに FALLBACK_SPECS がある・SPECS に余計な行がない

使い方: python3 tools/icons/check_icons.py [--root .]
終了コード: 0 = 問題なし / 1 = 問題あり。Python 3.9 互換・標準ライブラリだけ。
"""
import argparse
import os
import re
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_icons as gen  # noqa: E402

# --- 規格の値（要件 I2・I3、client_design.md 5-1） ---
VIEWBOX = "0 0 128 128"
SIZE = "128"
# 余白 8（端から 8。図形は 8〜120 の内側）
MARGIN = 8.0
EXTENT = 128.0
# SVG 1 枚のサイズの上限（バイト）。複雑すぎる絵を弾く（実際は 2KB 前後）
MAX_BYTES = 4096
# 最小の線の太さは 4（I3）。太い輪郭線は使わない（I8）ので上限 10 も設ける
STROKE_MIN = 4.0
STROKE_MAX = 10.0
# 図形の最小の大きさ（これより細いと I3 の「最小の線・文字の太さ 4」を割る）
SHAPE_MIN = 4.0
# 禁止する要素（ラスター画像・文字・スクリプト・フィルター・外部参照など。Godot の SVG 取り込みで
# 崩れる・ライセンスや外部依存を持ち込む・「文字は使わない」ため）
FORBIDDEN_TAGS = {
    "image", "script", "text", "tspan", "foreignobject", "filter", "style", "use", "a",
    "font", "animate", "animatetransform", "set", "feimage", "pattern", "mask",
}  # fmt: skip
# 許可する要素（これ以外は未知として弾く）
ALLOWED_TAGS = {
    "svg", "defs", "lineargradient", "stop", "clippath", "path", "rect", "circle", "ellipse",
}  # fmt: skip

NUMBER = re.compile(r"-?\d+(?:\.\d+)?")


def _local(tag):
    """名前空間つきのタグ（{http://www.w3.org/2000/svg}rect）から小文字の素の名前を取る。"""
    return tag.rsplit("}", 1)[-1].lower()


def _in_bounds(low, high):
    return MARGIN - 1e-6 <= low and high <= EXTENT - MARGIN + 1e-6


def validate_svg(text):
    """SVG 1 枚の規格を検査する。戻り値: 問題の文字列のリスト（空なら合格）。"""
    problems = []
    if len(text.encode("utf-8")) > MAX_BYTES:
        problems.append("サイズが上限 %d バイトを超えています" % MAX_BYTES)
    try:
        root = ET.fromstring(text)
    except ET.ParseError as error:
        return problems + ["XML として読めません: %s" % error]
    if _local(root.tag) != "svg":
        return problems + ["ルート要素が svg ではありません"]
    if root.get("viewBox") != VIEWBOX:
        problems.append("viewBox が %r ではありません（%r）" % (VIEWBOX, root.get("viewBox")))
    if root.get("width") != SIZE or root.get("height") != SIZE:
        problems.append("width / height が %s ではありません" % SIZE)
    for element in root.iter():
        tag = _local(element.tag)
        if tag in FORBIDDEN_TAGS:
            problems.append("禁止の要素 <%s> があります" % tag)
        elif tag not in ALLOWED_TAGS:
            problems.append("許可していない要素 <%s> があります" % tag)
        for name, value in element.attrib.items():
            if _local(name) == "href":
                problems.append("外部参照（href）があります: %s" % value)
        problems.extend(_validate_shape(element, tag))
    return problems


def _validate_shape(element, tag):
    """図形 1 つの検査（線の太さ・余白・最小の大きさ・背景の全面塗り）。"""
    problems = []
    stroke = element.get("stroke-width")
    if stroke is not None:
        width = float(stroke)
        if width < STROKE_MIN or width > STROKE_MAX:
            problems.append("線の太さ %s が %g〜%g の外です" % (stroke, STROKE_MIN, STROKE_MAX))
    if tag == "rect":
        x, y = float(element.get("x", 0)), float(element.get("y", 0))
        w, h = float(element.get("width", 0)), float(element.get("height", 0))
        if min(w, h) < SHAPE_MIN:
            problems.append("rect が細すぎます（%g×%g）" % (w, h))
        if w >= EXTENT and h >= EXTENT and x <= 0 and y <= 0:
            problems.append("背景の全面塗りがあります（背景は透明）")
        elif not (_in_bounds(x, x + w) and _in_bounds(y, y + h)):
            problems.append("rect が余白 %g の外です（x=%g y=%g w=%g h=%g）" % (MARGIN, x, y, w, h))
    elif tag == "circle":
        cx, cy, r = (float(element.get(k, 0)) for k in ("cx", "cy", "r"))
        if r * 2 < SHAPE_MIN:
            problems.append("circle が小さすぎます（r=%g）" % r)
        if not (_in_bounds(cx - r, cx + r) and _in_bounds(cy - r, cy + r)):
            problems.append("circle が余白 %g の外です（cx=%g cy=%g r=%g）" % (MARGIN, cx, cy, r))
    elif tag == "ellipse":
        cx, cy = float(element.get("cx", 0)), float(element.get("cy", 0))
        rx, ry = float(element.get("rx", 0)), float(element.get("ry", 0))
        if not (_in_bounds(cx - rx, cx + rx) and _in_bounds(cy - ry, cy + ry)):
            problems.append("ellipse が余白 %g の外です" % MARGIN)
    elif tag == "path":
        data = element.get("d", "")
        # 円弧（A）を含む経路は、数値が半径・フラグを含み座標として読めないので余白の検査をしない
        # （clipPath の中の切り抜き用の経路だけが使う。見える図形は円弧を使わない）
        if "A" not in data and "a" not in data:
            numbers = [float(n) for n in NUMBER.findall(data)]
            if numbers and not _in_bounds(min(numbers), max(numbers)):
                problems.append("path の座標が余白 %g の外です" % MARGIN)
    return problems


def _read(root, rel):
    path = os.path.join(root, rel)
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def _svgs_on_disk(root):
    """assets/icons/ 以下にある SVG の相対パス（リポジトリのルートから。/ 区切り）。"""
    found = []
    base = os.path.join(root, "assets", "icons")
    for directory, _dirs, files in os.walk(base):
        for name in files:
            if name.endswith(".svg"):
                rel = os.path.relpath(os.path.join(directory, name), root)
                found.append(rel.replace(os.sep, "/"))
    return sorted(found)


def check_definitions():
    """ITEMS・SPECS・FALLBACK_SPECS の整合（検査 4）。"""
    problems = []
    item_ids = [item_id for item_id, _type in gen.ITEMS]
    if len(set(item_ids)) != len(item_ids):
        problems.append("ITEMS に重複した ID があります")
    for item_id in item_ids:
        if item_id not in gen.SPECS:
            problems.append("ITEMS の %s に SPECS の行がありません" % item_id)
    for spec_id in gen.SPECS:
        if spec_id not in item_ids:
            problems.append("SPECS の %s が ITEMS にありません" % spec_id)
    for category in gen.CATEGORIES:
        if category not in gen.FALLBACK_SPECS:
            problems.append("カテゴリ %s に FALLBACK_SPECS の行がありません" % category)
    for category in gen.FALLBACK_SPECS:
        if category not in gen.CATEGORIES:
            problems.append("FALLBACK_SPECS の %s が ITEMS の type にありません" % category)
    return problems


def check_tree(root):
    """リポジトリ（root）全体の検査。戻り値: 問題の文字列のリスト。"""
    problems = check_definitions()
    if problems:
        return problems  # 定義が壊れていると生成できないので、ここで止める
    expected = gen.expected_files()
    # --- 1・2. 生成との一致と規格 ---
    for rel, content in expected.items():
        actual = _read(root, rel)
        if actual is None:
            problems.append("%s がありません（make icons で生成してください）" % rel)
            continue
        if actual != content:
            problems.append("%s が生成の出力と違います（make icons で生成し直してください）" % rel)
        if rel.endswith(".svg"):
            for problem in validate_svg(actual):
                problems.append("%s: %s" % (rel, problem))
    # --- 3. 表に無い SVG ---
    for rel in _svgs_on_disk(root):
        if rel not in expected:
            problems.append("%s は表（ITEMS・カテゴリ）にありません。不要なら削除してください" % rel)
    # --- 3. 読み込み表の preload の先 ---
    table = _read(root, gen.TABLE_PATH) or ""
    for path in re.findall(r'preload\("res://([^"]+)"\)', table):
        if not os.path.isfile(os.path.join(root, path)):
            problems.append("%s の preload の先 %s がありません" % (gen.TABLE_PATH, path))
    return problems


def main(argv=None):
    parser = argparse.ArgumentParser(description="アイコンの規格と生成との一致を検査する")
    parser.add_argument("--root", default=".", help="リポジトリのルート（既定: カレントディレクトリ）")
    args = parser.parse_args(argv)
    problems = check_tree(args.root)
    for problem in problems:
        print("NG:", problem)
    if problems:
        print("アイコンの検査: 問題 %d 件" % len(problems))
        return 1
    print("アイコンの検査: OK（SVG %d 枚）" % len([k for k in gen.expected_files() if k.endswith(".svg")]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
