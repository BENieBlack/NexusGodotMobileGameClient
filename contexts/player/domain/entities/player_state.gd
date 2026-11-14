## プレイヤーと所持データの読み取りモデル（client_design.md 4 節 D2）。
##
## 目的: login の応答のうち、プレイヤー（sys_player）・所持データ（trx 5 種）・有償ダイヤ（trx_diamond）・
##       サーバー時刻のオフセットを、画面が読める形で持つ。
##       サーバーが正の「読み取りモデル」で、独自の計算・判定は足さない。
## 保持の形（方針: Dictionary のまま。型付きにするのは、一覧を使う画面を作る機能で行う）:
##   sys_player  sys_player の辞書（my_id / name / level / level_exp / vip_point /
##               total_paid_amount / last_login_at）
##   trx_lists   {"trx_unit_list": Array, "trx_item_list": ..., "trx_wallet_list": ...,
##                "trx_equipment_list": ..., "trx_stamina_list": ...}。各要素は応答の辞書のまま
##   trx_diamond 有償ダイヤ（X-Platform の platform の 1 行の単数オブジェクト）。行が無ければ {}。
##               一覧ではないので trx_lists には入れない
##   server_time_offset_seconds / has_server_time
##               サーバー時刻 − 端末時刻（login 応答の Date から。client_design.md 3-3）。Date が読めなければ
##               has_server_time = false・オフセット 0（端末時計のみ）
## Godot は JSON の数値を float で持つ。数量・ID を整数として使う側が int() で変換する。
## 永続化しない（セッションのメモリのみ）。
class_name PlayerState
extends RefCounted

## login 応答の所持データ一覧のキー（サーバー api.md 2 節）。ApplyLoginDataUseCase と LoginResponse が使う。
## ダイヤは一覧ではなく単数の trx_diamond なので含めない
const TRX_LIST_KEYS: Array[String] = [
	"trx_unit_list",
	"trx_item_list",
	"trx_wallet_list",
	"trx_equipment_list",
	"trx_stamina_list",
]

var sys_player: Dictionary = {}
var trx_lists: Dictionary = {}
var trx_diamond: Dictionary = {}
var server_time_offset_seconds: int = 0
var has_server_time: bool = false


func _init(
	p_sys_player: Dictionary = {},
	p_trx_lists: Dictionary = {},
	p_trx_diamond: Dictionary = {},
	p_server_time_offset_seconds: int = 0,
	p_has_server_time: bool = false
) -> void:
	sys_player = p_sys_player
	trx_lists = p_trx_lists
	trx_diamond = p_trx_diamond
	server_time_offset_seconds = p_server_time_offset_seconds
	has_server_time = p_has_server_time


## プレイヤー ID（sys_player.my_id）。未取得なら空文字。
func user_id() -> String:
	return str(sys_player.get("my_id", ""))


## 所持データの一覧を返す。key は TRX_LIST_KEYS のどれか。無ければ空配列。
func trx_list(key: String) -> Array:
	var value: Variant = trx_lists.get(key, [])
	return value if value is Array else []


## 行の is_delete が「削除済み」か。サーバーは真偽値で返す（Q8）が、移行の間は 0/1 の整数も来うる
## （api.md 3.1）ので両方読む。true と 0 以外の数値は削除、false・0・キー無し・null・その他の型は有効。
## サーバーは削除済みの行を返さないので実際は保険。スタミナ・ウォレット・アイテム・ダイヤの行の除外に使う。
static func is_row_deleted(row: Dictionary) -> bool:
	var value: Variant = row.get("is_delete", false)
	if value is bool:
		return value
	if value is int or value is float:
		return value != 0
	return false


## ログイン前（またはセッション破棄後）で何も持っていないか。
## 判定は sys_player と trx_lists だけ（trx_diamond は含めない。ログイン後は sys_player が非空で足りる）。
func is_empty() -> bool:
	return sys_player.is_empty() and trx_lists.is_empty()
