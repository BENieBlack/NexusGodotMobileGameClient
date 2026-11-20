"""アイコンの生成（generate_icons.py）と検査（check_icons.py）のテスト。

守るもの:
  - 生成は決定的（同じ入力から同じ出力。再生成して差分が出ない前提）
  - 生成した全アイコンが規格に通る（規格違反の SVG を出さない）
  - 規格違反の SVG を検査が弾く（検出漏れの防止）
  - 表（ITEMS）と SVG の過不足・手編集を検査が見つける
実行: python3 -m unittest discover -s tools/tests（make check-deps が先に実行する）
"""
import os
import shutil
import sys
import tempfile
import unittest

# tools/icons は Python パッケージではないので、探索パスに足して直接 import する
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "icons"))
import check_icons as ci  # noqa: E402
import generate_icons as gen  # noqa: E402

GOOD_SVG = (
    '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">'
    '<circle cx="64" cy="64" r="40" fill="#FFFFFF"/></svg>'
)


class Generation(unittest.TestCase):
    """生成の性質。"""

    def test_generation_is_deterministic(self):
        # 前提: 同じ入力で 2 回生成。期待: 全ファイルが完全に同じ（乱数・時刻を使わない）
        self.assertEqual(gen.expected_files(), gen.expected_files())

    def test_item_count_and_categories(self):
        # 前提: サーバーの MstItemSeeder から転記した表。期待: 29 行・9 種類（要件 I6 の見積り）
        self.assertEqual(len(gen.ITEMS), 29)
        self.assertEqual(len(gen.CATEGORIES), 9)

    def test_every_generated_svg_passes_the_standard(self):
        # 前提: 生成した全 SVG。期待: 規格違反が 1 つも無い（規格を満たすものだけを出す）
        for rel, content in gen.expected_files().items():
            if rel.endswith(".svg"):
                self.assertEqual(ci.validate_svg(content), [], rel)

    def test_files_cover_items_fallbacks_unknown_stamp_and_table(self):
        # 前提: 生成物の一覧。期待: items 29・fallback 9+1・stamp 1・表 1 = 41 ファイル
        files = gen.expected_files()
        self.assertEqual(len(files), 29 + 9 + 1 + 1 + 1)
        self.assertIn("assets/icons/fallback/unknown.svg", files)
        self.assertIn("assets/icons/ui/stamp_check.svg", files)
        self.assertIn(gen.TABLE_PATH, files)

    def test_table_lists_every_key_with_preload(self):
        # 前提: 生成した表。期待: 全キーが preload の行で並ぶ（動的な load を使わない）
        table = gen.expected_files()[gen.TABLE_PATH]
        self.assertEqual(table.count("preload("), 40)
        self.assertNotIn("load(\"res://assets/icons/%s", table)


class Validate(unittest.TestCase):
    """validate_svg が規格違反を弾く。"""

    def problems(self, svg):
        return ci.validate_svg(svg)

    def test_good_svg_passes(self):
        self.assertEqual(self.problems(GOOD_SVG), [])

    def test_wrong_viewbox(self):
        svg = GOOD_SVG.replace('viewBox="0 0 128 128"', 'viewBox="0 0 64 64"')
        self.assertTrue(any("viewBox" in p for p in self.problems(svg)))

    def test_forbidden_elements(self):
        # ラスター画像・文字・フィルターは持ち込ませない（外部素材・フォントを使わない方針）
        for tag in ('<image href="x.png"/>', "<text>a</text>", "<filter/>"):
            svg = GOOD_SVG.replace("</svg>", tag + "</svg>")
            self.assertTrue(self.problems(svg), tag)

    def test_stroke_width_out_of_range(self):
        for width in ("3", "12"):
            svg = GOOD_SVG.replace("</svg>", '<path d="M20 20 L60 60" stroke-width="%s"/></svg>' % width)
            self.assertTrue(any("線の太さ" in p for p in self.problems(svg)), width)

    def test_shape_outside_margin(self):
        svg = GOOD_SVG.replace('r="40"', 'r="62"')  # 端から 2 しか空いていない
        self.assertTrue(any("余白" in p for p in self.problems(svg)))

    def test_full_background_rect(self):
        svg = GOOD_SVG.replace("</svg>", '<rect x="0" y="0" width="128" height="128"/></svg>')
        self.assertTrue(any("背景" in p for p in self.problems(svg)))

    def test_oversized_file(self):
        svg = GOOD_SVG.replace("</svg>", "<!--" + "x" * ci.MAX_BYTES + "--></svg>")
        self.assertTrue(any("サイズ" in p for p in self.problems(svg)))

    def test_broken_xml(self):
        self.assertTrue(self.problems("<svg"))


class Tree(unittest.TestCase):
    """check_tree（リポジトリ全体の検査）。一時ディレクトリへ生成して、壊し方ごとに検出を確かめる。"""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = self._tmp.name
        gen.main(["--root", self.root])

    def tearDown(self):
        self._tmp.cleanup()

    def test_clean_tree_has_no_problems(self):
        self.assertEqual(ci.check_tree(self.root), [])

    def test_hand_edited_svg_is_detected(self):
        # 手で SVG を直す → 生成の出力と違うので検出（再生成し忘れ・手編集の防止）
        path = os.path.join(self.root, "assets/icons/items/coin.svg")
        with open(path, "a", encoding="utf-8") as handle:
            handle.write("<!-- edit -->\n")
        self.assertTrue(any("coin.svg" in p and "生成" in p for p in ci.check_tree(self.root)))

    def test_missing_svg_is_detected(self):
        # 表にあるのに SVG が無い
        os.remove(os.path.join(self.root, "assets/icons/items/gold.svg"))
        problems = ci.check_tree(self.root)
        self.assertTrue(any("gold.svg" in p and "ありません" in p for p in problems))

    def test_extra_svg_is_detected(self):
        # 表に無い SVG（mst_item に無い ID の絵）が置かれた
        shutil.copy(
            os.path.join(self.root, "assets/icons/items/coin.svg"),
            os.path.join(self.root, "assets/icons/items/unknown_item.svg"),
        )
        self.assertTrue(any("unknown_item.svg" in p for p in ci.check_tree(self.root)))

    def test_table_preload_target_missing(self):
        # 表の preload の先が無い → SVG の欠落として検出される（表は生成の出力と一致していても）
        os.remove(os.path.join(self.root, "assets/icons/items/iron.svg"))
        self.assertTrue(any("preload" in p for p in ci.check_tree(self.root)))


if __name__ == "__main__":
    unittest.main()
