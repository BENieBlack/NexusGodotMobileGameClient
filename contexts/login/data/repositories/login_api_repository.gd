## login API の呼び出し（LoginRepository の実装）。
##
## 目的: POST /auth/login を、冪等キーつきで送り、応答を LoginResponse → LoginDataResult に直す。
## 流れ:
##   1. ApiClient.request(POST, /auth/login, {}, {idempotency_key}) を送る（本文なし。認証付きなので
##      Authorization は ApiClient が付け、401 なら refresh して 1 回だけ再送する）
##   2. 失敗は ApiResult.to_app_error() で返す
##   3. 成功は LoginResponse.from_dict(...).to_domain()
##   4. 応答ヘッダー Date からサーバー時刻とのオフセット（サーバー時刻 − 端末時刻）を作って結果に載せる
##      （client_design.md 3-3）。Date が無い・読めないときは端末時計のみ（has_server_time = false）
class_name LoginApiRepository
extends LoginRepository

var _api_client: ApiClient
var _clock: Clock


## clock は端末時刻の供給元（オフセットの算出に使う）。省略時は端末の時計（SystemClock）。
func _init(api_client: ApiClient, clock: Clock = null) -> void:
	_api_client = api_client
	_clock = clock if clock != null else SystemClock.new()


func fetch_login(idempotency_key: String) -> LoginDataResult:
	var api_result := await _api_client.request(
		"POST", "/auth/login", {}, {"idempotency_key": idempotency_key}
	)
	if not api_result.ok:
		return LoginDataResult.new(api_result.to_app_error())
	var result := LoginResponse.from_dict(api_result.data).to_domain()
	_apply_server_time(result, api_result.headers)
	return result


## 応答の Date ヘッダーからオフセットを作り、result に書く。
## offset = サーバー時刻 − 応答を受け取った時点の端末時刻。Date は秒精度で通信の遅延も含むため
## 誤差は 1〜数秒（回復間隔に対して許容。3-3）。ログは秒数だけ（トークン・本文は出さない）。
func _apply_server_time(result: LoginDataResult, headers: PackedStringArray) -> void:
	var server_unix := HttpDate.parse_to_unix(ApiClient.find_header(headers, "Date"))
	if server_unix == HttpDate.INVALID:
		push_warning("login 応答の Date ヘッダーを読めません。端末の時計だけを使います")
		return
	result.server_time_offset_seconds = server_unix - _clock.now_unix()
	result.has_server_time = true
	print("サーバー時刻のオフセット: %d 秒" % result.server_time_offset_seconds)
