## 通常のログインボーナスの報酬 1 行（mst_login_bonus_content）の読み取りモデル。
##
## 列（サーバーのマイグレーションの実スキーマ。主キーは複合で id 無し）:
##   deploy_key・mst_login_bonus_id・day・content_type・content_mst_id・content_option（JSON）・
##   content_quantity・amount（配布回数）・is_paid・sort_desc
## day = 0 はカムバック用の行。判断は持たない（周期に含めるかなどは使う側 = login が決める）。
class_name MstLoginBonusContent
extends RefCounted

var deploy_key: int = 0
var mst_login_bonus_id: String = ""
var day: int = 0
var content_type: String = ""
var content_mst_id: String = ""
## content_option の JSON を辞書に直した値。無い・壊れているときは空
var content_option: Dictionary = {}
var content_quantity: int = 0
## 配布回数（通常の行）
var amount: int = 0
var is_paid: bool = false
var sort_desc: int = 0


## 実際の数量 = content_quantity × amount（サーバーと同じ式。1 配布あたりの数 × 配布回数）。
func total_quantity() -> int:
	return content_quantity * amount
