## アイコンの共通部品（client_design.md 5-2・1-2。要件 I9）。ログインボーナスの各マス・報酬の行・ホームで共用する。
##
## 目的: 報酬・所持品の 1 件（type・id）を渡すと、フォールバックの規則で絵を出す。画面ごとに読み込みを書かない。
## 流れ（setup）:
##   1. ItemIconResolver に ItemIconTable.has_key を渡して、絵のキーを決める
##   2. ItemIconTable.texture_of で preload 済みの絵を引き、texture に入れる
##   3. 表示サイズを custom_minimum_size に反映する（親のコンテナが大きさを決める）
## 制約: mst_item を引かない・master_data を参照しない（C1）。引けた mst_item.type は呼び出し側が渡す。
##       動的な load をしない（絵は ItemIconTable の preload だけ。5-3）。どの入力でも絵が入る（空表示にしない）。
class_name ItemIcon
extends TextureRect

## 最後に決まった絵のキー（テストと確認用。例 `items/coin`）
var resolved_key: String = ""


## 絵を出す。type: item / wallet など、id: mst_item.id、mst_item_type: 引けた type（無ければ空）、
## icon_size: 表示の一辺（ビューポート単位。80・72・56・48 など）。
func setup(type: String, id: String, mst_item_type: String, icon_size: int) -> void:
	resolved_key = ItemIconResolver.resolve_key(type, id, mst_item_type, ItemIconTable.has_key)
	texture = ItemIconTable.texture_of(resolved_key)
	custom_minimum_size = Vector2(icon_size, icon_size)
