## LoginRepository.fetch_login() の結果。成功なら login の応答の中身（domain の型）を持つ。
##
## 項目:
##   sys_player      プレイヤー（辞書）。非 null（無ければ空）
##   trx_lists       所持データ 5 種 {"trx_unit_list": Array, ...}（キーは PlayerState.TRX_LIST_KEYS と同じ）
##   login_bonuses   ログインボーナスの受取結果。付与が無い日は空
##   trx_diamond     有償ダイヤ（端末の platform の 1 行。単数のオブジェクト）。無ければ空の辞書
##   login_bonus_calendars 通常・VIP の段の進捗（login 応答の新キー。キー欠落・null の段は null）。既定は空の束
##   server_time_offset_seconds  サーバー時刻 − 端末時刻（秒）。応答ヘッダー Date から LoginApiRepository が作る
##   has_server_time Date が読めて、オフセットが有効か。偽なら端末時計のみ（オフセット 0）
## 契約ごとの専用型（共用しない方針）。API の応答の型（LoginResponse。data）は domain に出さず、
## data が変換して作る。
class_name LoginDataResult
extends Result

var sys_player: Dictionary = {}
var trx_lists: Dictionary = {}
var login_bonuses: Array[LoginBonus] = []
var trx_diamond: Dictionary = {}
var login_bonus_calendars: LoginBonusCalendars = LoginBonusCalendars.new()
var server_time_offset_seconds: int = 0
var has_server_time: bool = false


func _init(
	p_error: AppError = null,
	p_sys_player: Dictionary = {},
	p_trx_lists: Dictionary = {},
	p_login_bonuses: Array[LoginBonus] = [],
	p_trx_diamond: Dictionary = {},
	p_server_time_offset_seconds: int = 0,
	p_has_server_time: bool = false,
	p_login_bonus_calendars: LoginBonusCalendars = null
) -> void:
	super(p_error == null, p_error)
	sys_player = p_sys_player
	trx_lists = p_trx_lists
	login_bonuses = p_login_bonuses
	trx_diamond = p_trx_diamond
	server_time_offset_seconds = p_server_time_offset_seconds
	has_server_time = p_has_server_time
	if p_login_bonus_calendars != null:
		login_bonus_calendars = p_login_bonus_calendars
