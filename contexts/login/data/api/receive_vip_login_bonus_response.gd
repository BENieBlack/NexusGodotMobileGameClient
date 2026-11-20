## POST /login_bonus/receive の応答の型（腐敗防止層。client_design.md 4 節）。
##
## 応答: { trx_vip_login_bonus, login_bonus_list, vip_login_bonus_calendar, updated_resources }。
## 取り出し（どのキーが欠けても失敗にしない）:
##   login_bonus_list          今回配った報酬（LoginResponse と同じ変換）。無い・null → 空
##   vip_login_bonus_calendar  VIP の段（LoginBonusCalendarResponse。読めなければ null。代替は UseCase）
##   updated_resources         辞書のまま（ApplyUpdatedResourcesUseCase の入力）。無い・null・型違い → {}
##   trx_vip_login_bonus       使わない（照合のみ。received_at の書式は未確認なので読まない）
class_name ReceiveVipLoginBonusResponse
extends RefCounted

var rewards: Array[LoginBonus] = []
var vip_calendar: LoginBonusCalendar = null
var updated_resources: Dictionary = {}


static func from_dict(data: Dictionary) -> ReceiveVipLoginBonusResponse:
	var response := ReceiveVipLoginBonusResponse.new()
	response.rewards = LoginResponse.parse_login_bonus_list(data)
	response.vip_calendar = LoginBonusCalendarResponse.from_variant(
		data.get(LoginBonusCalendarsResponse.VIP_KEY, null), true
	)
	response.updated_resources = JsonReader.get_dict(data, "updated_resources")
	return response


func to_domain() -> ReceiveVipLoginBonusResult:
	return ReceiveVipLoginBonusResult.new(null, rewards, vip_calendar, updated_resources)
