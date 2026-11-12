## POST /auth/login の応答の型（腐敗防止層。client_design.md 4 節、architecture.md 2 節 API 応答）。
##
## 目的: 生の Dictionary を domain に渡さず、ここで型付きに変換する。null と欠落を同じに扱う規則（D3）は
##       JsonReader を通してここに閉じ込める（キーが無い・null・型違いは、配列なら []、辞書なら {}）。
## 項目（サーバー api.md 6 節。9 項目のうち、取り込むもの）:
##   sys_player（辞書）、trx 一覧 6 種（unit / item / wallet / diamond / equipment / stamina。要素は辞書のまま）、
##   login_bonus_list（LoginBonus の配列。要素の expire_at・metadata の null は空に直す）
## 使い方: LoginResponse.from_dict(api_result.data).to_domain() で LoginDataResult にする。
class_name LoginResponse
extends RefCounted

## 所持データ一覧の応答キー。player の PlayerState.TRX_LIST_KEYS と同じ値（他コンテキストの
## entities を参照できないので、応答の形として data に持つ）
const TRX_LIST_KEYS: Array[String] = [
	"trx_unit_list",
	"trx_item_list",
	"trx_wallet_list",
	"trx_diamond_list",
	"trx_equipment_list",
	"trx_stamina_list",
]

var sys_player: Dictionary = {}
## キーは PlayerState.TRX_LIST_KEYS と同じ（サーバーの応答のキー名のまま）。6 種すべてが入る
var trx_lists: Dictionary = {}
var login_bonus_list: Array[LoginBonus] = []


## 応答の辞書から取り込む。キーが無い・null は既定値（D3）。
static func from_dict(data: Dictionary) -> LoginResponse:
	var response := LoginResponse.new()
	response.sys_player = JsonReader.get_dict(data, "sys_player")
	for key in TRX_LIST_KEYS:
		response.trx_lists[key] = JsonReader.get_array(data, key)
	for raw in JsonReader.get_array(data, "login_bonus_list"):
		if raw is Dictionary:
			response.login_bonus_list.append(_to_login_bonus(raw))
	return response


## domain の結果型に直す。
func to_domain() -> LoginDataResult:
	return LoginDataResult.new(null, sys_player, trx_lists, login_bonus_list)


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
