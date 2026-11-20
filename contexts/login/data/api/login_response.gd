## POST /auth/login の応答の型（腐敗防止層。client_design.md 4 節、architecture.md 2 節 API 応答）。
##
## 目的: 生の Dictionary を domain に渡さず、ここで型付きに変換する。null と欠落を同じに扱う規則（D3）は
##       JsonReader を通してここに閉じ込める（キーが無い・null・型違いは、配列なら []、辞書なら {}）。
## 項目（サーバー api.md 6 節。9 項目のうち、取り込むもの）:
##   sys_player（辞書）、trx 一覧 5 種（unit / item / wallet / equipment / stamina。要素は辞書のまま）、
##   trx_diamond（有償ダイヤ。X-Platform の platform の 1 行の**単数オブジェクト**。行が無ければ null → {}。
##   旧キー trx_diamond_list は読まない）、
##   login_bonus_list（LoginBonus の配列。要素の expire_at・metadata の null は空に直す）、
##   login_bonus_calendar・vip_login_bonus_calendar（段の進捗。LoginBonusCalendarsResponse に任せる。
##   キー欠落・null は「その段なし」。旧サーバーの応答は両方 null）
## 使い方: LoginResponse.from_dict(api_result.data).to_domain() で LoginDataResult にする。
class_name LoginResponse
extends RefCounted

## 所持データ一覧の応答キー。player の PlayerState.TRX_LIST_KEYS と同じ値（他コンテキストの
## entities を参照できないので、応答の形として data に持つ）
const TRX_LIST_KEYS: Array[String] = [
	"trx_unit_list",
	"trx_item_list",
	"trx_wallet_list",
	"trx_equipment_list",
	"trx_stamina_list",
]

var sys_player: Dictionary = {}
## キーは PlayerState.TRX_LIST_KEYS と同じ（サーバーの応答のキー名のまま）。5 種すべてが入る
var trx_lists: Dictionary = {}
## 有償ダイヤ（単数のオブジェクト）。null・キー無し・型違いは空の辞書
var trx_diamond: Dictionary = {}
var login_bonus_list: Array[LoginBonus] = []
var login_bonus_calendars: LoginBonusCalendars = LoginBonusCalendars.new()


## 応答の辞書から取り込む。キーが無い・null は既定値（D3）。
static func from_dict(data: Dictionary) -> LoginResponse:
	var response := LoginResponse.new()
	response.sys_player = JsonReader.get_dict(data, "sys_player")
	response.trx_diamond = JsonReader.get_dict(data, "trx_diamond")
	for key in TRX_LIST_KEYS:
		response.trx_lists[key] = JsonReader.get_array(data, key)
	response.login_bonus_list = parse_login_bonus_list(data)
	response.login_bonus_calendars = LoginBonusCalendarsResponse.from_dict(data)
	return response


## data の login_bonus_list を LoginBonus の配列にする（receive 応答でも同じ変換を使う）。無い・null は空。
static func parse_login_bonus_list(data: Dictionary) -> Array[LoginBonus]:
	var bonuses: Array[LoginBonus] = []
	for raw in JsonReader.get_array(data, "login_bonus_list"):
		if raw is Dictionary:
			bonuses.append(_to_login_bonus(raw))
	return bonuses


## domain の結果型に直す。
func to_domain() -> LoginDataResult:
	return LoginDataResult.new(
		null, sys_player, trx_lists, login_bonus_list, trx_diamond, 0, false, login_bonus_calendars
	)


## 1 件の辞書を LoginBonus にする。amount は Godot が float で持つので int に直す。
## expire_at は常に null（サーバー仕様）なので、null は空文字にする。metadata は null 可なので、null は空の辞書。
static func _to_login_bonus(raw: Dictionary) -> LoginBonus:
	var expire_at: Variant = raw.get("expire_at", null)
	return LoginBonus.new(
		str(raw.get("unique_id", "")),
		str(raw.get("type", "")),
		str(raw.get("id", "")),
		int(raw.get("amount", 0)),
		"" if expire_at == null else str(expire_at),
		JsonReader.get_dict(raw, "metadata")
	)
