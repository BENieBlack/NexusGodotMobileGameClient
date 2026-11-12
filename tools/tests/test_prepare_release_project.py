"""prepare_release_project.py のテスト。一時ディレクトリに最小のプロジェクトを作って検査する。

流れ（各テスト共通）: 一時ディレクトリに最小のプロジェクト（debug/・tests/・gdUnit4・godot-sqlite 入り）を作る
  → prepare を実行 → 複製の中身・project.godot・終了コードを確かめる。
実行: python3 -m unittest discover -s tools/tests（make check-deps が先に実行する）
"""
import contextlib
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import prepare_release_project as prp  # noqa: E402

PROJECT_GODOT = """config_version=5

[autoload]

; 説明のコメント（res://debug/ という文字が入っていても、コメント行はガードしない）
EventBus="*res://core/event_bus.gd"
E2EDriver="*res://debug/e2e_driver.gd"
Toast="*res://core/toast.gd"

[editor_plugins]

enabled=PackedStringArray("res://addons/godot-sqlite/plugin.cfg", "res://addons/gdUnit4/plugin.cfg")

[display]

window/size/viewport_width=1080
"""


class Case(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = os.path.realpath(self._tmp.name)
        self.out = os.path.join(self.root, "build", "release-project")
        self.write("project.godot", PROJECT_GODOT)
        self.write("core/event_bus.gd", "extends Node\n")
        self.write("core/toast.gd", "extends Node\n")
        self.write("debug/e2e_driver.gd", "extends Node\n")
        self.write("tests/unit/a_test.gd", "extends Node\n")
        self.write("addons/gdUnit4/plugin.cfg", "")
        self.write("addons/godot-sqlite/plugin.cfg", "")
        self.write("docs/readme.md", "x")
        self.write("Makefile", "x")

    def write(self, rel, text):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def read_out(self, rel):
        with open(os.path.join(self.out, rel), encoding="utf-8") as f:
            return f.read()

    def run_prepare(self, force=False, out=None):
        """prepare を実行し、(終了コード, 標準出力) を返す。"""
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            code = prp.prepare(self.root, out or self.out, force)
        return code, buffer.getvalue()

    def snapshot(self):
        """複製の全ファイルの (相対パス, 内容) を返す（冪等性の比較用）。"""
        result = {}
        for directory, _dirs, files in os.walk(self.out):
            for name in files:
                path = os.path.join(directory, name)
                with open(path, encoding="utf-8") as f:
                    result[os.path.relpath(path, self.out)] = f.read()
        return result


class Copy(Case):
    def test_dev_only_things_are_excluded(self):
        """前提: debug/・tests/・gdUnit4・docs・Makefile がある。期待: 複製に無く、実行に要るものは有る。"""
        self.assertEqual(0, self.run_prepare()[0])
        for gone in ["debug", "tests", "addons/gdUnit4", "docs", "Makefile", "build"]:
            self.assertFalse(os.path.exists(os.path.join(self.out, gone)), gone)
        for kept in ["project.godot", "core/event_bus.gd", "addons/godot-sqlite/plugin.cfg"]:
            self.assertTrue(os.path.exists(os.path.join(self.out, kept)), kept)

    def test_idempotent(self):
        """前提: 2 回実行する（2 回目は出力先が既にある）。期待: 同じ結果（build/ 自身を取り込まない）。"""
        self.run_prepare()
        first = self.snapshot()
        self.assertEqual(0, self.run_prepare()[0])
        self.assertEqual(first, self.snapshot())

    def test_source_is_not_modified(self):
        """期待: 元の project.godot は変えない（開発では E2EDriver が要る）。"""
        self.run_prepare()
        with open(os.path.join(self.root, "project.godot"), encoding="utf-8") as f:
            self.assertEqual(PROJECT_GODOT, f.read())


class Transform(Case):
    def test_only_excluded_autoload_removed(self):
        """期待: E2EDriver だけが消え、他の autoload（順序も）は残る。"""
        _, output = self.run_prepare()
        text = self.read_out("project.godot")
        self.assertNotIn('E2EDriver="', text)
        self.assertLess(text.index("EventBus="), text.index("Toast="))
        self.assertIn("E2EDriver", output)

    def test_only_gdunit_plugin_removed(self):
        """期待: editor_plugins から gdUnit4 だけが消え、godot-sqlite は残る。他の節は変わらない。"""
        self.run_prepare()
        text = self.read_out("project.godot")
        self.assertIn(
            'enabled=PackedStringArray("res://addons/godot-sqlite/plugin.cfg")\n', text
        )
        self.assertNotIn("gdUnit4/plugin.cfg", text)
        self.assertIn("window/size/viewport_width=1080", text)

    def test_all_plugins_excluded_gives_empty_array(self):
        """期待: 全部外れても、有効な空の配列になる（Godot が読める形）。"""
        text, _, _ = prp.transform_project_godot(
            '[editor_plugins]\n\nenabled=PackedStringArray("res://addons/gdUnit4/plugin.cfg")\n'
        )
        self.assertIn("enabled=PackedStringArray()", text)


class Guard(Case):
    def test_product_code_referencing_debug_fails(self):
        """前提: 製品コード（core/）が debug/ を参照。期待: 終了コード 1 で、ファイルと行を表示する。"""
        self.write("core/bad.gd", 'extends Node\nconst D = preload("res://debug/e2e_driver.gd")\n')
        code, output = self.run_prepare()
        self.assertEqual(1, code)
        self.assertIn("core/bad.gd:2", output)

    def test_scene_referencing_tests_fails(self):
        """期待: .tscn の tests/ への参照も検出する。"""
        self.write("core/s.tscn", '[ext_resource path="res://tests/x.gd"]\n')
        self.assertEqual(1, self.run_prepare()[0])

    def test_gdunit_reference_fails(self):
        """期待: gdUnit4 への参照も検出する。"""
        self.write("core/g.gd", 'var x = "res://addons/gdUnit4/a.gd"\n')
        self.assertEqual(1, self.run_prepare()[0])

    def test_clean_project_passes(self):
        """期待: 参照が無ければ 0（誤検出しない。project.godot のコメント行は無視）。"""
        self.assertEqual(0, self.run_prepare()[0])


class GuardMissingRefs(Case):
    """複製に実在しない res:// の参照（INCLUDE への入れ忘れ）の検出。"""

    def test_reference_to_non_included_dir_fails(self):
        """前提: 製品コードが INCLUDE に無いディレクトリ（fonts/）を参照。期待: 終了コード 1 で、場所と参照先を表示する。"""
        self.write("core/f.gd", 'var f = load("res://fonts/a.ttf")\n')
        code, output = self.run_prepare()
        self.assertEqual(1, code)
        self.assertIn("core/f.gd:1", output)
        self.assertIn("fonts/a.ttf", output)

    def test_reference_to_existing_file_passes(self):
        """前提: 複製に実在するファイルを参照。期待: 通る（誤検出しない）。"""
        self.write("core/ok.gd", 'var t = preload("res://core/toast.gd")\nvar p = "res://project.godot"\n')
        self.assertEqual(0, self.run_prepare()[0])

    def test_comment_reference_is_ignored(self):
        """期待: .gd の # コメントと project.godot の ; コメントにある参照は見ない。"""
        self.write("core/c.gd", '# res://fonts/a.ttf を使う予定\nextends Node\n')
        self.assertEqual(0, self.run_prepare()[0])

    def test_dynamic_path_is_ignored(self):
        """期待: 動的に組み立てる文字列（%s を含む）は存在を確かめない。"""
        self.write("core/d.gd", 'var p = "res://fonts/%s.ttf" % name\n')
        self.assertEqual(0, self.run_prepare()[0])


class Classification(Case):
    """未分類のトップレベル・アドオンは失敗にする（足し忘れを必ず気付かせる）。"""

    def test_unclassified_top_level_fails(self):
        """前提: INCLUDE にも EXCLUDE にも無いトップレベル（fonts/）。期待: 終了コード 1、名前と追加先を表示し、複製は作らない。"""
        self.write("fonts/a.ttf", "x")
        code, output = self.run_prepare()
        self.assertEqual(1, code)
        self.assertIn("fonts", output)
        self.assertIn("INCLUDE / EXCLUDE", output)
        self.assertFalse(os.path.exists(self.out))

    def test_unclassified_addon_fails(self):
        """前提: ADDONS_* に無いアドオン（newaddon）。期待: 終了コード 1。git 管理外で入るもの（gdUnit4 のように）も対象。"""
        self.write("addons/newaddon/plugin.cfg", "")
        code, output = self.run_prepare()
        self.assertEqual(1, code)
        self.assertIn("addons/newaddon", output)

    def test_classified_passes(self):
        """期待: 分類済み（setUp の構成）なら通る。アドオンのファイル（addons/README.md）は分類の対象外。"""
        self.write("addons/README.md", "x")
        self.assertEqual(0, self.run_prepare()[0])

    def test_os_junk_ignored_without_git(self):
        """前提: git が無い（listdir の経路）で .DS_Store がある。期待: 失敗しない。"""
        self.write(".DS_Store", "x")
        self.assertEqual(0, self.run_prepare()[0])

    @unittest.skipUnless(shutil.which("git"), "git が無い")
    def test_untracked_junk_ignored_with_git(self):
        """前提: git 管理下で、未追跡の個人ファイル（notes.txt）がある。期待: 失敗しない。
        管理されている未分類（fonts/）は、git 経由でも検出する。"""
        env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull)
        subprocess.run(["git", "init", "-q", self.root], check=True, env=env)
        subprocess.run(["git", "-C", self.root, "add", "-A"], check=True, env=env)
        self.write("notes.txt", "個人のメモ")
        self.assertEqual(0, self.run_prepare()[0])
        self.write("fonts/a.ttf", "x")
        subprocess.run(["git", "-C", self.root, "add", "fonts"], check=True, env=env)
        self.assertEqual(1, self.run_prepare()[0])


class OutProtection(Case):
    def test_root_and_ancestors_rejected(self):
        """期待: リポジトリのルート・その親・/ は --force でも拒否し、何も消さない。"""
        for bad in [self.root, os.path.dirname(self.root), os.path.sep]:
            with self.assertRaises(prp.UsageError):
                prp.check_out_dir(self.root, bad, True)
        self.assertTrue(os.path.exists(os.path.join(self.root, "project.godot")))

    def test_source_dir_rejected_even_with_force(self):
        """期待: 複製元（core/ など）を出力先にできない。"""
        with self.assertRaises(prp.UsageError):
            prp.check_out_dir(self.root, os.path.join(self.root, "core"), True)

    def test_outside_build_needs_force(self):
        """期待: build/ 配下以外は --force が要る。要ると通る。"""
        other = os.path.join(self.root, "other-out")
        with self.assertRaises(prp.UsageError):
            prp.check_out_dir(self.root, other, False)
        self.assertEqual(other, prp.check_out_dir(self.root, other, True))

    def test_main_returns_2_on_bad_out(self):
        """期待: main は不正な出力先で終了コード 2。"""
        with contextlib.redirect_stderr(io.StringIO()):
            code = prp.main(["--root", self.root, "--out", self.root])
        self.assertEqual(2, code)


if __name__ == "__main__":
    unittest.main()
