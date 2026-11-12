## sign_up / sign_in の API 呼び出し（AuthRepository の実装。client_design.md 2-1・3-1）。
##
## 目的: ApiClient の結果（ApiResult）を、domain が扱う AuthSessionResult（AppError つき）に
##       直す。
## 流れ（sign_up / sign_in 共通）:
##   1. 本文を作る: device_id（保存済みの値）と device_info（os / os_version / model /
##      app_version の 4 項目）。device_info は sign_up・sign_in の両方に付ける
##      （sign_in は 4 項目すべて必須）
##   2. ApiClient.request(POST, ..., {auth = false}) で送る。認証前なので Authorization は
##      付けず、401 でも refresh しない。sign_up だけ、署名ヘッダー（ClientSignature）を
##      extra_headers に付ける。冪等キーは付けない（認証前の API）
##   3. 成功の応答から token.access_token / refresh_token を取り出す
##      （項目が少ないので専用の *_response.gd は作らず、ここで JsonReader を使って取り出す）
## 失敗の扱い: 通信・業務エラーは ApiResult.to_app_error() で返す。応答に access_token が無いときは PARSE。
class_name AuthApiRepository
extends AuthRepository

## device_info.app_version。sign_in は 20 文字以内（sign_up は 50）なので、短い値に揃える（client_design.md 3-3）
const APP_VERSION := "1.0.0"

## device_info の各項目の最大長（サーバー api.md 3・4 節。app_version は sign_in の 20）
const MAX_OS_LENGTH := 50
const MAX_OS_VERSION_LENGTH := 50
const MAX_MODEL_LENGTH := 100
const MAX_APP_VERSION_LENGTH := 20

var _api_client: ApiClient
var _token_store: LocalAuthTokenRepository


## token_store は device_id の取り出しに使う（同じ data 層の保存実装）。
func _init(api_client: ApiClient, token_store: LocalAuthTokenRepository) -> void:
	_api_client = api_client
	_token_store = token_store


func sign_up() -> AuthSessionResult:
	var body := _build_body()
	# 署名は送る本文の文字列に対して作る。ApiClient は POST の本文を JSON.stringify(body) で送るので、
	# 同じ式で作った文字列に署名すれば一致する
	var headers := ClientSignature.create_headers(JSON.stringify(body))
	var api_result := await _api_client.request(
		"POST", "/auth/sign_up", body, {"auth": false, "extra_headers": headers}
	)
	return _to_session_result(api_result)


func sign_in() -> AuthSessionResult:
	var api_result := await _api_client.request(
		"POST", "/auth/sign_in", _build_body(), {"auth": false}
	)
	return _to_session_result(api_result)


## 送る本文 {device_id, device_info{os, os_version, model, app_version}}。
func _build_body() -> Dictionary:
	return {
		"device_id": _token_store.device_id(),
		"device_info": device_info(),
	}


## 端末情報。4 項目とも sign_in で必須（空文字は不可なので、取れない値は "unknown" にする）。
static func device_info() -> Dictionary:
	return build_device_info(OS.get_name(), OS.get_version(), OS.get_model_name())


## 端末情報の辞書を作る。サーバーの最大長（api.md の検証ルール: os 50、os_version 50、model 100、
## app_version 20。sign_in の上限）を超えると 422 になるので、超える分は切り詰める
## （OS が返す版文字列・機種名は端末次第で長くなりうる）。
static func build_device_info(os_name: String, os_version: String, model: String) -> Dictionary:
	return {
		"os": _fit(os_name, MAX_OS_LENGTH),
		"os_version": _fit(os_version, MAX_OS_VERSION_LENGTH),
		"model": _fit(model, MAX_MODEL_LENGTH),
		"app_version": _fit(APP_VERSION, MAX_APP_VERSION_LENGTH),
	}


## 空なら "unknown"、max_length を超えるなら先頭 max_length 文字にする。
static func _fit(value: String, max_length: int) -> String:
	if value == "":
		return "unknown"
	return value.substr(0, max_length)


## ApiResult を AuthSessionResult に直す。
func _to_session_result(api_result: ApiResult) -> AuthSessionResult:
	if not api_result.ok:
		return AuthSessionResult.new(null, api_result.to_app_error())
	var token := JsonReader.get_dict(api_result.data, "token")
	var access_token := str(token.get("access_token", ""))
	var refresh_token := str(token.get("refresh_token", ""))
	# トークンが無い成功応答は使えない。空のまま保存すると「保存トークンなし」に戻り、次も sign_up になる
	if access_token == "" or refresh_token == "":
		return AuthSessionResult.new(null, AppError.new(AppError.Kind.PARSE, "token が応答にありません"))
	var session := AuthSession.new(access_token, refresh_token)
	return AuthSessionResult.new(session)
