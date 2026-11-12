## LoginRepository.fetch_login() の結果。成功なら login の応答の中身（domain の型）を持つ。
##
## 項目:
##   sys_player      プレイヤー（辞書）。非 null（無ければ空）
##   trx_lists       所持データ 6 種 {"trx_unit_list": Array, ...}（キーは PlayerState.TRX_LIST_KEYS と同じ）
##   login_bonuses   ログインボーナスの受取結果。付与が無い日は空
## 契約ごとの専用型（共用しない方針）。API の応答の型（LoginResponse。data）は domain に出さず、
## data が変換して作る。
class_name LoginDataResult
extends Result

var sys_player: Dictionary = {}
var trx_lists: Dictionary = {}
var login_bonuses: Array[LoginBonus] = []


func _init(
	p_error: AppError = null,
	p_sys_player: Dictionary = {},
	p_trx_lists: Dictionary = {},
	p_login_bonuses: Array[LoginBonus] = []
) -> void:
	super(p_error == null, p_error)
	sys_player = p_sys_player
	trx_lists = p_trx_lists
	login_bonuses = p_login_bonuses
