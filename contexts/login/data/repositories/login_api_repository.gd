## login API の呼び出し（LoginRepository の実装）。
##
## 目的: POST /auth/login を、冪等キーつきで送り、応答を LoginResponse → LoginDataResult に直す。
## 流れ:
##   1. ApiClient.request(POST, /auth/login, {}, {idempotency_key}) を送る（本文なし。認証付きなので
##      Authorization は ApiClient が付け、401 なら refresh して 1 回だけ再送する）
##   2. 失敗は ApiResult.to_app_error() で返す
##   3. 成功は LoginResponse.from_dict(...).to_domain()
class_name LoginApiRepository
extends LoginRepository

var _api_client: ApiClient


func _init(api_client: ApiClient) -> void:
	_api_client = api_client


func fetch_login(idempotency_key: String) -> LoginDataResult:
	var api_result := await _api_client.request(
		"POST", "/auth/login", {}, {"idempotency_key": idempotency_key}
	)
	if not api_result.ok:
		return LoginDataResult.new(api_result.to_app_error())
	return LoginResponse.from_dict(api_result.data).to_domain()
