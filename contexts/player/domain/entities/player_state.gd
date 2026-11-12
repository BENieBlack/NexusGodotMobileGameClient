## プレイヤーと所持データの読み取りモデル（client_design.md 4 節 D2）。
##
## 目的: login の応答のうち、プレイヤー（sys_player）と所持データ（trx 6 種）を、画面が読める形で持つ。
##       サーバーが正の「読み取りモデル」で、独自の計算・判定は足さない。
## 保持の形（方針: Dictionary のまま。型付きにするのは、一覧を使う画面を作る機能で行う）:
##   sys_player  sys_player の辞書（my_id / name / level / level_exp / vip_point /
##               total_paid_amount / last_login_at）
##   trx_lists   {"trx_unit_list": Array, "trx_item_list": ..., "trx_wallet_list": ...,
##                "trx_diamond_list": ..., "trx_equipment_list": ..., "trx_stamina_list": ...}。
##               各要素は応答の辞書のまま
## Godot は JSON の数値を float で持つ。数量・ID を整数として使う側が int() で変換する。
## 永続化しない（セッションのメモリのみ）。
class_name PlayerState
extends RefCounted

## login 応答の所持データ一覧のキー（サーバー api.md 6 節）。ApplyLoginDataUseCase と LoginResponse が使う
const TRX_LIST_KEYS: Array[String] = [
	"trx_unit_list",
	"trx_item_list",
	"trx_wallet_list",
	"trx_diamond_list",
	"trx_equipment_list",
	"trx_stamina_list",
]

var sys_player: Dictionary = {}
var trx_lists: Dictionary = {}


func _init(p_sys_player: Dictionary = {}, p_trx_lists: Dictionary = {}) -> void:
	sys_player = p_sys_player
	trx_lists = p_trx_lists


## プレイヤー ID（sys_player.my_id）。未取得なら空文字。
func user_id() -> String:
	return str(sys_player.get("my_id", ""))


## 所持データの一覧を返す。key は TRX_LIST_KEYS のどれか。無ければ空配列。
func trx_list(key: String) -> Array:
	var value: Variant = trx_lists.get(key, [])
	return value if value is Array else []


## ログイン前（またはセッション破棄後）で何も持っていないか。
func is_empty() -> bool:
	return sys_player.is_empty() and trx_lists.is_empty()
