# テスト基盤（GdUnit4）が動くことを確かめるスモークテスト。
#
# 目的: 本物のテストが無い段階でも `make test` が「テストを 0 件実行して成功」とならず、
#       GdUnit4 の起動・実行・結果出力までの経路が生きていることを CI で保証する。
# 流れ: make test → Godot（ヘッドレス）→ GdUnit4 が res://tests 以下の *_test.gd を集めて
#       test_ で始まる関数を実行 → 結果を reports/ に出す。
# 今後: 新構成のコードが入ったら、contexts/ をミラーした単体テストを足す
#       （設計は .claude/architecture.md の 3 節。ADR 0003 も参照）。
extends GdUnitTestSuite


## テストが実行され、アサーションが使えること。
## 前提: なし。操作: 1 + 1 を計算する。期待: 2 になる（GdUnit4 のアサーション API が動く）。
func test_assertion_works() -> void:
	assert_int(1 + 1).is_equal(2)


## エンジンが起動していて、SceneTree とノードを扱えること。
## 前提: ヘッドレスの Godot 上で実行されている。操作: Node を生成して名前を付ける。
## 期待: 名前が保たれ、get_tree() が null でない。
## auto_free はテスト終了時にノードを解放させる（孤立ノードのリークを GdUnit4 に報告させないため）。
func test_engine_runs() -> void:
	var node: Node = auto_free(Node.new())
	node.name = "Smoke"
	assert_str(node.name).is_equal("Smoke")
	assert_object(get_tree()).is_not_null()
