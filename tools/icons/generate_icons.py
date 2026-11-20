#!/usr/bin/env python3
"""アイテムのアイコン（SVG）と、読み込み表 item_icon_table.gd を生成する（自作。外部の素材は使わない）。

目的:
  `mst_item` の全行ぶんのアイコン、フォールバック（カテゴリ別・不明）、カレンダーのスタンプを、
  図形のテンプレートと「ID ごとの差分の表」から機械的に作る（要件 I1・I7、client_design.md 5-1〜5-4）。
  1 つずつ描かないので、画風（フラット＋ごく控えめなグラデーション・柔らかい影・太い輪郭線なし）と
  色（夜空に合わせた限定パレット）が全アイコンで揃い、同じ入力から必ず同じ出力ができる（乱数なし）。

使い方:
  python3 tools/icons/generate_icons.py [--root .]      （make icons）
  出力: assets/icons/items/<mst_item.id>.svg、assets/icons/fallback/*.svg、assets/icons/ui/stamp_check.svg、
        core/presentation/item_icon/item_icon_table.gd（キー → preload の表）
  Python 3.9 互換・標準ライブラリだけ。外部ファイル（フォント・画像）は読まない。

流れ:
  1. 下の ITEMS（mst_item の全行。ID と type）と、ID ごとの差分の表 SPECS から、アイコンの定義を引く
  2. 定義のテンプレート関数（bottle・flask など）が、128×128 の座標で図形（文字列）を返す
  3. SVG 1 枚にまとめる（グラデーションの定義は使った色だけ。順序は固定）
  4. 全アイコンのキーから item_icon_table.gd を作る

`mst_item` に行が増えたとき:
  ITEMS に 1 行と SPECS に 1 行を足して再生成する。足し忘れても画面は壊れない（クライアントが
  カテゴリのフォールバックか unknown を出す）が、check_icons.py が「ITEMS に無い SVG」「SVG の無い ITEMS」を検出する。
"""
import argparse
import math
import os
import sys

# --- 1. mst_item の全行（ID → type）。正本はサーバーの MstItemSeeder（NexusMobileGameServer-Laravel の
#        api/database/seeders/MstItemSeeder.php）で、ここへ転記した 29 行（二重管理。サーバーが変わったらここも直す） ---
ITEMS = [
    ("item_heal_001", "recovery"),
    ("item_heal_002", "recovery"),
    ("item_heal_003", "recovery"),
    ("item_boost_001", "boost"),
    ("item_boost_002", "boost"),
    ("item_boost_003", "boost"),
    ("item_exp_001", "experience"),
    ("item_exp_002", "experience"),
    ("item_exp_003", "experience"),
    ("unit_exp_100", "unit_enhancement"),
    ("unit_exp_1000", "unit_enhancement"),
    ("unit_exp_10000", "unit_enhancement"),
    ("unit_exp_100000", "unit_enhancement"),
    ("item_material_001", "material"),
    ("item_material_002", "material"),
    ("item_material_003", "material"),
    ("gold", "currency"),
    ("coin", "currency"),
    ("stamina_50", "stamina"),
    ("free_diamond", "currency"),
    ("food", "natural_resource"),
    ("wood", "natural_resource"),
    ("stone", "natural_resource"),
    ("iron", "natural_resource"),
    ("alliance_points", "points"),
    ("pvp_points", "points"),
    ("event_points", "points"),
    ("achievement_points", "points"),
    ("vip_points", "points"),
]

# mst_item.type の 9 種類（フォールバック category_<type> の対象）。ITEMS から作る（順序は初出順）
CATEGORIES = []
for _item_id, _item_type in ITEMS:
    if _item_type not in CATEGORIES:
        CATEGORIES.append(_item_type)

# --- 色（限定パレット 1 つを全アイコンで共有する）。名前 → (明るい側, 基準, 暗い側)。
#     夜空（青紫）の背景で映えるよう、全体に明るめ・やや彩度を抑えた色にしてある。
#     縦のグラデーション（明 → 基準）の差を小さくして「ごく控えめ」にする ---
PALETTE = {
    "gold": ("#FFE08A", "#FFC245", "#E0902B"),
    "amber": ("#FFC48A", "#FF9A4D", "#D96A2B"),
    "rose": ("#FFA3BA", "#FF6F91", "#D9446E"),
    "violet": ("#CDB0FF", "#A06BFF", "#6E3FD0"),
    "sky": ("#A8E4FF", "#5CC4FF", "#2E8FD6"),
    "mint": ("#B5F5DC", "#5EE0B0", "#2FA97F"),
    "lime": ("#D6F59A", "#9AE05A", "#5FAE2E"),
    "stone": ("#D5DAF5", "#9AA3CF", "#6670A3"),
    "wood": ("#E0B38A", "#BE8657", "#8A5B36"),
    "cream": ("#FFFFFF", "#FFF3CF", "#EBD9A6"),
    "navy": ("#5A5CB0", "#3A3C84", "#26275E"),
    "glass": ("#EEF0FF", "#C9CEFF", "#9EA6F0"),
    "silver": ("#F2F4FF", "#C5CAE6", "#8F97C4"),
}

# --- ID ごとの差分の表。テンプレート名と、その引数（色・量・印の数）。
#     同じカテゴリは同じ形で、色・中身の量・小さな印（pips）の数で見分ける（I7）。色だけに頼らない
#     ため、形が違う差（boost の記号・points のバッジの記号）も入れてある（I8） ---
SPECS = {
    # 回復の瓶: 中身の量（level）と印の数（pips）が小・中・大
    "item_heal_001": ("bottle", {"liquid": "rose", "level": 0.40, "pips": 1}),
    "item_heal_002": ("bottle", {"liquid": "rose", "level": 0.65, "pips": 2}),
    "item_heal_003": ("bottle", {"liquid": "rose", "level": 0.90, "pips": 3}),
    # 強化薬の丸いフラスコ: 記号が違う（攻撃 = 三角・防御 = 盾・素早さ = 山形 2 つ）
    "item_boost_001": ("flask", {"liquid": "amber", "glyph": "attack"}),
    "item_boost_002": ("flask", {"liquid": "sky", "glyph": "defense"}),
    "item_boost_003": ("flask", {"liquid": "mint", "glyph": "speed"}),
    # 経験値の結晶: 大きさと印の数が小・中・大
    "item_exp_001": ("crystal", {"color": "mint", "scale": 0.70, "pips": 1}),
    "item_exp_002": ("crystal", {"color": "mint", "scale": 0.85, "pips": 2}),
    "item_exp_003": ("crystal", {"color": "mint", "scale": 1.00, "pips": 3}),
    # ユニット経験値のカード: 印の数が桁（100 → 1、1000 → 2、10000 → 3、100000 → 4）
    "unit_exp_100": ("card", {"color": "violet", "pips": 1}),
    "unit_exp_1000": ("card", {"color": "violet", "pips": 2}),
    "unit_exp_10000": ("card", {"color": "violet", "pips": 3}),
    "unit_exp_100000": ("card", {"color": "violet", "pips": 4}),
    # 素材の袋: 色と印の数
    "item_material_001": ("sack", {"color": "wood", "pips": 1}),
    "item_material_002": ("sack", {"color": "stone", "pips": 2}),
    "item_material_003": ("sack", {"color": "amber", "pips": 3}),
    # 通貨: ゴールドは延べ棒、コインは丸いコイン、無償ダイヤは宝石（形で見分ける）
    "gold": ("ingots", {"color": "gold"}),
    "coin": ("coin", {"color": "amber"}),
    "free_diamond": ("diamond", {"color": "sky"}),
    # スタミナ回復薬: 緑の瓶に稲妻
    "stamina_50": ("bottle", {"liquid": "lime", "level": 0.70, "pips": 1, "glyph": "bolt"}),
    # 自然資源: 形がそれぞれ違う
    "food": ("apple", {}),
    "wood": ("logs", {}),
    "stone": ("boulder", {}),
    "iron": ("nut", {}),
    # ポイント: 丸いバッジ。記号が違う
    "alliance_points": ("badge", {"color": "sky", "glyph": "rings"}),
    "pvp_points": ("badge", {"color": "rose", "glyph": "cross"}),
    "event_points": ("badge", {"color": "gold", "glyph": "star"}),
    "achievement_points": ("badge", {"color": "mint", "glyph": "check"}),
    "vip_points": ("badge", {"color": "violet", "glyph": "crown"}),
}

# --- フォールバック（カテゴリ別）。同じテンプレートを、中立の色（銀・石・ガラス）で出す。
#     「このカテゴリの何か」が分かる程度の汎用の絵 ---
FALLBACK_SPECS = {
    "recovery": ("bottle", {"liquid": "stone", "level": 0.6, "pips": 0}),
    "boost": ("flask", {"liquid": "stone", "glyph": "attack"}),
    "experience": ("crystal", {"color": "stone", "scale": 0.9, "pips": 0}),
    "unit_enhancement": ("card", {"color": "stone", "pips": 0}),
    "material": ("sack", {"color": "stone", "pips": 0}),
    "currency": ("coin", {"color": "silver"}),
    "stamina": ("bolt", {"color": "lime"}),
    "natural_resource": ("leaf", {}),
    "points": ("badge", {"color": "silver", "glyph": "dot"}),
}

# 出力先（--root からの相対）
ITEMS_DIR = "assets/icons/items"
FALLBACK_DIR = "assets/icons/fallback"
UI_DIR = "assets/icons/ui"
TABLE_PATH = "core/presentation/item_icon/item_icon_table.gd"
# 表のキーに使う名前（クライアントの ItemIconResolver が返すキーと同じ。5-2）
STAMP_KEY = "ui/stamp_check"
UNKNOWN_KEY = "fallback/unknown"


# ---------------------------------------------------------------------------
# SVG の組み立て
# ---------------------------------------------------------------------------
def _num(value):
    """数値を短い文字列にする（小数 2 桁。末尾の 0 を除く。-0 を出さない）。"""
    text = ("%.2f" % value).rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


class Canvas:
    """1 枚の SVG。図形を足し、使った色のグラデーションの定義を出す。"""

    def __init__(self):
        self.defs = []
        self.shapes = []
        self._gradients = []  # 使った色の名前（初めて使った順）
        self._clips = []

    def paint(self, color):
        """色の名前 → fill の値。縦のグラデーション（明 → 基準）の定義を初回だけ足す。
        "#RRGGBB" はそのまま返す（単色）。"""
        if color.startswith("#"):
            return color
        if color not in self._gradients:
            self._gradients.append(color)
        return "url(#g_%s)" % color

    def add(self, text):
        self.shapes.append(text)

    def shadow(self, cx=64, rx=34):
        """床の柔らかい影（フィルターは使わない。半透明の楕円 1 枚）。"""
        self.add(
            '<ellipse cx="%s" cy="114" rx="%s" ry="4" fill="#0B0B2A" fill-opacity="0.28"/>'
            % (_num(cx), _num(rx))
        )

    def rect(self, x, y, w, h, rx, color, opacity=None):
        extra = "" if opacity is None else ' fill-opacity="%s"' % _num(opacity)
        self.add(
            '<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="%s"%s/>'
            % (_num(x), _num(y), _num(w), _num(h), _num(rx), self.paint(color), extra)
        )

    def circle(self, cx, cy, r, color, opacity=None):
        extra = "" if opacity is None else ' fill-opacity="%s"' % _num(opacity)
        self.add(
            '<circle cx="%s" cy="%s" r="%s" fill="%s"%s/>'
            % (_num(cx), _num(cy), _num(r), self.paint(color), extra)
        )

    def path(self, d, color, opacity=None, clip=None):
        extra = "" if opacity is None else ' fill-opacity="%s"' % _num(opacity)
        if clip:
            extra += ' clip-path="url(#%s)"' % clip
        self.add('<path d="%s" fill="%s"%s/>' % (d, self.paint(color), extra))

    def poly(self, points, color, opacity=None):
        d = "M" + " L".join("%s %s" % (_num(x), _num(y)) for x, y in points) + " Z"
        self.path(d, color, opacity)

    def clip(self, clip_id, d):
        """clipPath を足す（瓶の中身を瓶の形で切るため）。"""
        self._clips.append('<clipPath id="%s"><path d="%s"/></clipPath>' % (clip_id, d))

    def stroke_path(self, d, color, width):
        """線だけの図形（疑問符のみ。太さは 4 以上 10 以下。check_icons.py が検査する）。"""
        self.add(
            '<path d="%s" fill="none" stroke="%s" stroke-width="%s" '
            'stroke-linecap="round" stroke-linejoin="round"/>' % (d, color, _num(width))
        )

    def render(self):
        """SVG 全体の文字列。定義（グラデーション・clipPath）を先頭に、図形を描く順に並べる。"""
        parts = [
            '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" '
            'viewBox="0 0 128 128">',
        ]
        defs = []
        for name in self._gradients:
            light, base, _dark = PALETTE[name]
            defs.append(
                '<linearGradient id="g_%s" x1="0" y1="0" x2="0" y2="1">'
                '<stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/>'
                "</linearGradient>" % (name, light, base)
            )
        defs.extend(self._clips)
        if defs:
            parts.append("<defs>" + "".join(defs) + "</defs>")
        parts.extend(self.shapes)
        parts.append("</svg>")
        return "\n".join(parts) + "\n"


def xform(points, scale=1.0, cx=64.0, cy=64.0, dx=0.0, dy=0.0):
    """点列を (cx, cy) を中心に拡大し、(dx, dy) だけ動かす。"""
    return [(cx + (x - cx) * scale + dx, cy + (y - cy) * scale + dy) for x, y in points]


def pips(canvas, count, x, y, step_x, step_y, color="gold", radius=5.0):
    """小さな丸の印を count 個、(x, y) から (step_x, step_y) ずつずらして並べる（数の違いの印。I7）。"""
    for i in range(count):
        canvas.circle(x + step_x * i, y + step_y * i, radius, color)


# 稲妻の形（128 の座標。スタミナの記号）
BOLT = [(74, 10), (36, 68), (58, 68), (50, 116), (92, 54), (68, 54)]


# ---------------------------------------------------------------------------
# テンプレート（128×128 の座標。余白 8 を守る＝図形は 8〜120 の内側）
# ---------------------------------------------------------------------------
# 瓶の本体の輪郭（首から肩・胴・底まで）。中身を切り抜く clipPath にも使う
BOTTLE_BODY = (
    "M52 34 L52 44 C30 56 24 74 24 90 C24 104 34 112 48 112 L80 112 "
    "C94 112 104 104 104 90 C104 74 98 56 76 44 L76 34 Z"
)


def bottle(c, liquid="rose", level=0.6, pips=0, glyph="plus", **_):
    """回復薬・スタミナ回復薬の瓶。ガラスの本体に、level（0〜1）の高さまで液体が入る。"""
    c.shadow()
    c.rect(52, 14, 24, 24, 4, "glass")  # 首
    c.path(BOTTLE_BODY, "glass")
    # 液体: 本体の形で切る（底 112 から level の高さ。肩の曲線に沿って切れる）
    c.clip("c_body", BOTTLE_BODY)
    top = 112 - level * 66
    c.add(
        '<rect x="20" y="%s" width="88" height="%s" fill="%s" clip-path="url(#c_body)"/>'
        % (_num(top), _num(114 - top), c.paint(liquid))
    )
    c.rect(48, 8, 32, 12, 6, "navy")  # 栓
    c.rect(34, 62, 8, 28, 4, "#FFFFFF", 0.45)  # ガラスの照り
    if glyph == "bolt":
        c.poly(xform(BOLT, 0.5, 64, 64, 0, 24), "cream")
    else:
        # 回復の十字（太さ 12）。液体の上に載せるので色は明るいクリーム
        c.rect(58, 74, 12, 28, 3, "cream")
        c.rect(50, 82, 28, 12, 3, "cream")
    pips_right = pips
    if pips_right:
        for i in range(pips_right):
            c.circle(98, 20 + 14 * i, 5, "gold")


def flask(c, liquid="amber", glyph="attack", **_):
    """強化薬の丸いフラスコ。中の記号（三角・盾・山形）で効果を見分ける。"""
    c.shadow()
    c.rect(54, 14, 20, 30, 4, "glass")  # 首
    c.circle(64, 78, 34, "glass")
    c.clip("c_body", "M30 78 A34 34 0 1 0 98 78 A34 34 0 1 0 30 78 Z")
    c.add(
        '<rect x="28" y="64" width="72" height="52" fill="%s" clip-path="url(#c_body)"/>'
        % c.paint(liquid)
    )
    c.rect(50, 8, 28, 12, 6, "navy")
    c.rect(38, 62, 8, 22, 4, "#FFFFFF", 0.45)
    if glyph == "attack":
        c.poly([(64, 62), (82, 96), (46, 96)], "cream")
    elif glyph == "defense":
        c.path(
            "M64 60 L84 68 L84 86 C84 98 74 104 64 108 C54 104 44 98 44 86 L44 68 Z", "cream"
        )
    else:
        # 素早さ: 山形（上向きの V）を 2 つ重ねる
        for dy in (0, 18):
            c.poly(
                xform([(64, 58), (86, 80), (78, 88), (64, 74), (50, 88), (42, 80)], dy=dy), "cream"
            )


CRYSTAL = [(64, 12), (94, 38), (94, 86), (64, 112), (34, 86), (34, 38)]


def crystal(c, color="mint", scale=1.0, pips=0, **_):
    """経験値の結晶（縦長の六角形）。大きさ（scale）と印の数で小・中・大を見分ける。底（y=112）を揃える。"""
    c.shadow(64, 34 * scale)
    pts = xform(CRYSTAL, scale, 64, 112)
    c.poly(pts, color)
    # 左半分を明るくして面を出す（頂点 0・1・2・3 を結ぶ左の面）
    left = [pts[0], pts[5], pts[4], pts[3]]
    c.poly(left, "#FFFFFF", 0.28)
    # 結晶の中の 4 つ角の星（経験値の印）
    star = [(64, 44), (71, 62), (90, 64), (71, 72), (64, 92), (57, 72), (38, 64), (57, 62)]
    c.poly(xform(star, 0.8 * scale, 64, 112, 0, 0), "cream")
    for i in range(pips):
        c.circle(104, 24 + 14 * i, 5, "gold")


def card(c, color="violet", pips=0, **_):
    """ユニット経験値のカード。上向きの山形が 2 つ、下の印の数が桁。"""
    c.shadow()
    c.rect(26, 12, 76, 100, 14, color)
    c.rect(36, 22, 56, 80, 8, "navy", 0.35)
    for dy in (0, 22):
        c.poly(
            xform([(64, 34), (84, 54), (76, 62), (64, 50), (52, 62), (44, 54)], dy=dy), "cream"
        )
    # 印は下の枠の中に中央揃えで並べる（間隔 13）
    start = 64 - 13 * (pips - 1) / 2.0
    for i in range(pips):
        c.circle(start + 13 * i, 92, 4.5, "gold")


def sack(c, color="wood", pips=0, **_):
    """素材の袋（口を縛った巾着）。色と印の数で見分ける。"""
    c.shadow()
    c.path("M44 40 C24 62 22 112 64 112 C106 112 104 62 84 40 Z", color)
    c.path("M46 36 L38 16 L56 26 L64 12 L72 26 L90 16 L82 36 Z", color)
    c.rect(44, 34, 40, 12, 6, "navy")  # 口を縛る帯
    c.poly([(64, 62), (80, 80), (64, 98), (48, 80)], "cream", 0.9)  # 菱形の印
    for i in range(pips):
        c.circle(110, 24 + 14 * i, 5, "gold")


def coin(c, color="amber", **_):
    """丸いコイン。厚みは、少し下にずらした暗い円で出す。"""
    c.shadow()
    c.circle(64, 70, 44, "#B26A1F" if color == "amber" else PALETTE[color][2])
    c.circle(64, 62, 44, color)
    c.circle(64, 62, 32, PALETTE[color][2], 0.35)
    star = [(64, 38), (70, 55), (88, 57), (74, 68), (79, 86), (64, 76), (49, 86), (54, 68), (40, 57), (58, 55)]
    c.poly(star, "cream")


def ingots(c, color="gold", **_):
    """ゴールド: 積んだ延べ棒 2 本（台形）。上の面を明るくして立体に見せる。"""
    c.shadow(64, 44)
    c.poly([(22, 108), (30, 80), (98, 80), (106, 108)], color)
    c.poly([(30, 80), (38, 70), (90, 70), (98, 80)], "cream", 0.55)
    c.poly([(40, 70), (46, 56), (82, 56), (88, 70)], color)
    c.poly([(46, 56), (52, 46), (76, 46), (82, 56)], "cream", 0.55)


def diamond(c, color="sky", **_):
    """無償ダイヤ: 宝石（上に平らな面・下に尖る）。面ごとに明るさを変える。"""
    c.shadow()
    outline = [(36, 34), (92, 34), (108, 54), (64, 112), (20, 54)]
    c.poly(outline, color)
    c.poly([(36, 34), (92, 34), (108, 54), (20, 54)], "#FFFFFF", 0.3)
    c.poly([(20, 54), (64, 112), (64, 54)], PALETTE[color][2], 0.28)
    c.poly([(48, 38), (66, 38), (56, 50)], "#FFFFFF", 0.55)
    # 右上のきらめき（4 つ角の星）
    c.poly([(104, 14), (108, 22), (116, 26), (108, 30), (104, 38), (100, 30), (92, 26), (100, 22)], "cream")


def bolt(c, color="lime", **_):
    """スタミナのカテゴリ: 稲妻だけ。"""
    c.shadow()
    c.poly(BOLT, color)
    c.poly([(74, 10), (36, 68), (58, 68)], "#FFFFFF", 0.3)


def apple(c, **_):
    """食料: りんご（2 つの丸 + 軸 + 葉）。"""
    c.shadow()
    c.circle(50, 72, 30, "rose")
    c.circle(78, 72, 30, "rose")
    c.rect(60, 22, 8, 22, 4, "wood")
    c.path("M68 34 C78 14 98 14 102 22 C96 38 80 42 68 34 Z", "lime")


def logs(c, **_):
    """木材: 丸太 3 本（下に 2 本・上に 1 本）。左の端に年輪。"""
    c.shadow(64, 44)
    for x, y in ((12, 78), (52, 78), (32, 46)):
        c.rect(x, y, 64, 30, 15, "wood")
        c.circle(x + 15, y + 15, 15, "#E0B38A")
        c.circle(x + 15, y + 15, 7, "wood")


def boulder(c, **_):
    """石材: 大きな岩（多角形）に明るい面と暗い面。"""
    c.shadow()
    c.poly([(26, 98), (22, 68), (44, 42), (76, 36), (102, 56), (106, 92), (84, 110), (46, 110)], "stone")
    c.poly([(44, 42), (76, 36), (102, 56), (64, 68)], "#FFFFFF", 0.3)
    c.poly([(26, 98), (22, 68), (44, 42), (64, 68), (46, 110)], PALETTE["stone"][2], 0.3)


def nut(c, **_):
    """鉄: 六角ナット（外の六角形 + 中の穴）。"""
    c.shadow()
    c.poly([(64, 18), (104, 41), (104, 87), (64, 110), (24, 87), (24, 41)], "silver")
    c.poly([(64, 18), (104, 41), (64, 64), (24, 41)], "#FFFFFF", 0.3)
    c.circle(64, 64, 20, "navy")
    c.circle(64, 64, 11, "#26275E")


def leaf(c, **_):
    """自然資源のカテゴリ: 葉っぱ（葉脈つき）。"""
    c.shadow()
    c.path("M22 100 C18 50 60 16 108 20 C112 70 80 112 22 100 Z", "lime")
    c.poly([(28, 96), (90, 36), (98, 44), (36, 104)], PALETTE["lime"][2], 0.4)


def _star_points(cx, cy, outer, inner, n=5):
    pts = []
    for i in range(n * 2):
        radius = outer if i % 2 == 0 else inner
        angle = -math.pi / 2 + i * math.pi / n
        pts.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    return pts


def badge(c, color="silver", glyph="dot", **_):
    """ポイントの丸いバッジ。中の記号（輪 2 つ・×・星・チェック・王冠・点）で種類を見分ける。"""
    c.shadow()
    c.circle(64, 62, 44, color)
    c.circle(64, 62, 34, PALETTE[color][2], 0.28)
    if glyph == "rings":
        c.circle(52, 62, 16, "cream", 0.95)
        c.circle(76, 62, 16, "cream", 0.75)
    elif glyph == "cross":
        for angle in (45, -45):
            c.add(
                '<rect x="38" y="56" width="52" height="12" rx="6" fill="%s" '
                'transform="rotate(%d 64 62)"/>' % (c.paint("cream"), angle)
            )
    elif glyph == "star":
        c.poly(_star_points(64, 64, 28, 12), "cream")
    elif glyph == "check":
        c.poly([(36, 64), (46, 54), (58, 66), (84, 38), (94, 48), (58, 88)], "cream")
    elif glyph == "crown":
        c.poly([(38, 84), (34, 46), (50, 60), (64, 38), (78, 60), (94, 46), (90, 84)], "cream")
        c.rect(38, 86, 52, 10, 3, "cream")
    else:
        c.circle(64, 62, 12, "cream")


def unknown(c, **_):
    """不明な ID・unit・equipment の絵: 丸みのある四角に「?」（線の太さ 10。文字は使わない）。"""
    c.shadow()
    c.rect(16, 14, 96, 96, 24, "stone")
    c.stroke_path("M46 48 C46 30 82 30 82 50 C82 62 64 62 64 76", "#FFF3CF", 10)
    c.circle(64, 94, 7, "cream")


def stamp_check(c, **_):
    """カレンダーのスタンプ: 判子の円 + 大きなチェック。"""
    c.circle(64, 64, 52, "rose", 0.95)
    c.circle(64, 64, 40, PALETTE["rose"][2], 0.3)
    c.poly([(32, 64), (44, 52), (56, 64), (84, 34), (96, 46), (56, 88)], "cream")


TEMPLATES = {
    "bottle": bottle,
    "flask": flask,
    "crystal": crystal,
    "card": card,
    "sack": sack,
    "coin": coin,
    "ingots": ingots,
    "diamond": diamond,
    "bolt": bolt,
    "apple": apple,
    "logs": logs,
    "boulder": boulder,
    "nut": nut,
    "leaf": leaf,
    "badge": badge,
}


def draw(template, params):
    """テンプレート名と引数から SVG の文字列を作る。"""
    canvas = Canvas()
    TEMPLATES[template](canvas, **params)
    return canvas.render()


# ---------------------------------------------------------------------------
# 出力
# ---------------------------------------------------------------------------
def build_all():
    """全アイコンを作る。戻り値: {"キー": "SVG の文字列"} の辞書（キーは表のキーと同じ。例 items/coin）。
    順序は固定（ITEMS の順 → カテゴリの順 → unknown → stamp）。"""
    icons = {}
    for item_id, _item_type in ITEMS:
        template, params = SPECS[item_id]
        icons["items/" + item_id] = draw(template, params)
    for category in CATEGORIES:
        template, params = FALLBACK_SPECS[category]
        icons["fallback/category_" + category] = draw(template, params)
    canvas = Canvas()
    unknown(canvas)
    icons[UNKNOWN_KEY] = canvas.render()
    canvas = Canvas()
    stamp_check(canvas)
    icons[STAMP_KEY] = canvas.render()
    return icons


def key_to_path(key):
    """表のキー → リポジトリ内の SVG のパス（assets/icons/ からの相対）。"""
    return "assets/icons/%s.svg" % key


def build_table(keys):
    """item_icon_table.gd の中身を作る。gdformat をそのまま通る形（タブ・末尾のカンマ・1 行 100 字以内）。"""
    lines = [
        "## アイコンの読み込み表（生成物。手で編集しない）。",
        "##",
        "## 生成: tools/icons/generate_icons.py（make icons）。キー（例 `items/coin`）→ `preload` した Texture2D。",
        "## 目的: アイコンを動的なパス（`\"res://...%s\" % id` の `load`）で読まず、`preload` の定数表から引く。",
        "##       `preload` の実在はスクリプトの読み込み時に検査され（make check-release でも通る）、",
        "##       書き出し（実機ビルド）の設定にも依存しない（client_design.md 5-3）。",
        "## 使い方: `ItemIconTable.has_key(key)` で在るか、`ItemIconTable.texture_of(key)` で絵を引く。",
        "##         在るかどうかの述語は ItemIconResolver に渡す（core/domain は Texture2D を知らない）。",
        "class_name ItemIconTable",
        "extends RefCounted",
        "",
        "## キー → 絵。キーは `items/<mst_item.id>`・`fallback/category_<type>`・`fallback/unknown`・`ui/stamp_check`",
        "const TEXTURES := {",
    ]
    for key in keys:
        entry = '\t"%s": preload("res://%s"),' % (key, key_to_path(key))
        if len(entry.expandtabs(4)) > 100:
            # gdformat は 1 行 100 字を超える辞書の項目を「キー: の後で改行」に整形する。
            # 同じ形で出して、整形（make format-check）と生成の出力を一致させる
            entry = '\t"%s":\n\tpreload("res://%s"),' % (key, key_to_path(key))
        lines.append(entry)
    lines += [
        "}",
        "",
        "",
        "## キーの絵が在るか。",
        "static func has_key(key: String) -> bool:",
        "\treturn TEXTURES.has(key)",
        "",
        "",
        "## キーの絵を返す。無いキーは null（呼び出し側は先に has_key で確かめる。ItemIcon は必ず unknown へ落とす）。",
        "static func texture_of(key: String) -> Texture2D:",
        "\treturn TEXTURES.get(key, null)",
        "",
        "",
        "## 全キー（確認用の一覧画面・テストが使う。表の順）。",
        "static func keys() -> Array:",
        "\treturn TEXTURES.keys()",
        "",
    ]
    return "\n".join(lines)


def expected_files():
    """生成されるファイルの全体: {リポジトリ内の相対パス: 内容}。check_icons.py が差分の検査に使う。"""
    icons = build_all()
    files = {key_to_path(key): svg for key, svg in icons.items()}
    files[TABLE_PATH] = build_table(list(icons.keys()))
    return files


def main(argv=None):
    parser = argparse.ArgumentParser(description="アイコン（SVG）と読み込み表を生成する")
    parser.add_argument("--root", default=".", help="リポジトリのルート（既定: カレントディレクトリ）")
    args = parser.parse_args(argv)
    files = expected_files()
    for rel, content in files.items():
        path = os.path.join(args.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
    print("生成: SVG %d 枚と %s" % (len(files) - 1, TABLE_PATH))
    return 0


if __name__ == "__main__":
    sys.exit(main())
