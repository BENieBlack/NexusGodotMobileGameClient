## カレンダー API（list・receive）の呼び出し（LoginBonusCalendarRepository の実装）。
##
## 流れ:
##   fetch_calendars: POST /login_bonus/list（本文なし。冪等キーは付けない。list 系なので同じキーの応答が
##                    24 時間再生され、古い状態が返るのを避ける）→ LoginBonusCalendarsResponse
##   receive_vip:     POST /login_bonus/receive（本文 mst_vip_login_bonus_id。冪等キーを付ける）→
##                    ReceiveVipLoginBonusResponse。エラー 299（26001〜26003）の後は新しいキー、通信断・409・503 は
##                    同じキー（キーの持ち主は呼び出し元）
## 失敗は ApiResult.to_app_error() で返す（Authorization・401 の refresh は ApiClient が行う）。
class_name LoginBonusCalendarApiRepository
extends LoginBonusCalendarRepository

var _api_client: ApiClient


func _init(api_client: ApiClient) -> void:
	_api_client = api_client


func fetch_calendars() -> FetchLoginBonusCalendarsResult:
	# 冪等キーを付けない（options を渡さない）
	var api_result := await _api_client.request("POST", "/login_bonus/list", {})
	if not api_result.ok:
		return FetchLoginBonusCalendarsResult.new(api_result.to_app_error())
	return FetchLoginBonusCalendarsResult.new(
		null, LoginBonusCalendarsResponse.from_dict(api_result.data)
	)


func receive_vip(
	mst_vip_login_bonus_id: String, idempotency_key: String
) -> ReceiveVipLoginBonusResult:
	var api_result := await _api_client.request(
		"POST",
		"/login_bonus/receive",
		{"mst_vip_login_bonus_id": mst_vip_login_bonus_id},
		{"idempotency_key": idempotency_key}
	)
	if not api_result.ok:
		return ReceiveVipLoginBonusResult.new(api_result.to_app_error())
	return ReceiveVipLoginBonusResponse.from_dict(api_result.data).to_domain()
