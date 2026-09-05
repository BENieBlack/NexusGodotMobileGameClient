extends Node

# 汎用APIクライアント - 認証済みAPIリクエストを管理

const BASE_URL = "http://localhost:8090/api"

# サーバ独自のビジネスエラーHTTPステータスコード
const HTTP_BUSINESS_ERROR = 299

signal request_completed(response_data: Dictionary)
signal request_failed(error: String)
signal business_error(error_code: int, message: String)

var http_request: HTTPRequest

# リフレッシュ中フラグ（二重リフレッシュ防止）
var _is_refreshing: bool = false

# マスター更新中フラグ（二重更新防止）
var _is_master_updating: bool = false

# リフレッシュ待ちキュー（リフレッシュ中に来たリクエストを再実行）
var _pending_request: Dictionary = {}

func _ready():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

# GETリクエスト
func get_request(endpoint: String) -> void:
	var url = BASE_URL + endpoint
	var headers = _get_headers()

	print("GETリクエスト送信: ", url)
	_pending_request = {"method": "GET", "endpoint": endpoint, "body": {}}
	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)

	if error != OK:
		request_failed.emit("HTTPリクエストの作成に失敗しました")

# POSTリクエスト
func post_request(endpoint: String, body_data: Dictionary = {}) -> void:
	var url = BASE_URL + endpoint
	var headers = _get_headers()
	var body = JSON.stringify(body_data)

	print("POSTリクエスト送信: ", url)
	print("リクエストボディ: ", body)
	_pending_request = {"method": "POST", "endpoint": endpoint, "body": body_data}
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)

	if error != OK:
		request_failed.emit("HTTPリクエストの作成に失敗しました")

# ヘッダーを生成（認証トークンを含む）
func _get_headers() -> PackedStringArray:
	var headers = PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json"
	])

	# 認証トークンがあれば追加
	if UserDataManager.is_logged_in and UserDataManager.auth_token != "":
		headers.append("Authorization: Bearer " + UserDataManager.auth_token)
		print("認証トークンを使用: ", UserDataManager.auth_token.substr(0, 20) + "...")
	else:
		print("警告: 認証トークンがありません")

	if UserDataManager.master_hash != "":
		headers.append("X-Master-Hash: " + UserDataManager.master_hash)

	return headers

# HTTPリクエスト完了時のコールバック
func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		print("リクエストエラー: ", result)
		request_failed.emit("ネットワークエラーが発生しました (コード: " + str(result) + ")")
		return

	var body_string = body.get_string_from_utf8()
	print("レスポンスコード: ", response_code)
	print("レスポンスボディ: ", body_string)

	# HTTP 299: サーバ独自のビジネスロジックエラー
	if response_code == HTTP_BUSINESS_ERROR:
		var json = JSON.new()
		if json.parse(body_string) == OK:
			var data = json.data
			var error_code = data.get("error_code", -1)
			var message = data.get("message", "不明なエラー")
			print("ビジネスエラー (", error_code, "): ", message)
			business_error.emit(error_code, message)
		else:
			business_error.emit(-1, "ビジネスエラー（レスポンス解析失敗）")
		return

	# HTTP 401: アクセストークン期限切れ → リフレッシュを試みる
	if response_code == 401 and not _is_refreshing:
		print("アクセストークン期限切れ - リフレッシュを試みます")
		await _refresh_and_retry()
		return

	if response_code < 200 or response_code >= 300:
		print("サーバーエラー: ", response_code)
		request_failed.emit("サーバーエラー: " + str(response_code))
		return

	var json = JSON.new()
	var parse_result = json.parse(body_string)

	if parse_result != OK:
		print("JSONパースエラー")
		request_failed.emit("レスポンスの解析に失敗しました")
		return

	var response_data = json.data
	print("APIレスポンス成功: ", response_data)

	# 更新要求はBodyではなくレスポンスヘッダーで通知される。
	if _has_master_update_required(headers) and not _is_master_updating:
		_is_master_updating = true
		await MasterDataManager.check_and_update()
		_is_master_updating = false

	request_completed.emit(response_data)

# レスポンスヘッダーからマスター更新要求を判定
func _has_master_update_required(headers: PackedStringArray) -> bool:
	for header in headers:
		var separator_index := header.find(":")
		if separator_index < 0:
			continue

		var name := header.substr(0, separator_index).strip_edges().to_lower()
		var value := header.substr(separator_index + 1).strip_edges().to_lower()
		if name == "x-master-update-required":
			return value == "true" || value == "1"

	return false

# トークンリフレッシュ → 元のリクエストを再送
func _refresh_and_retry() -> void:
	if UserDataManager.refresh_token == "":
		print("リフレッシュトークンがありません - ログアウト")
		UserDataManager.logout()
		request_failed.emit("セッションが期限切れです。再度ログインしてください。")
		return

	_is_refreshing = true
	print("リフレッシュトークンでアクセストークンを更新中...")

	# リフレッシュ用の一時HTTPRequest
	var refresh_http = HTTPRequest.new()
	add_child(refresh_http)

	var refresh_url = BASE_URL + "/auth/refresh_token"
	var refresh_body = JSON.stringify({"refresh_token": UserDataManager.refresh_token})
	var refresh_headers = PackedStringArray(["Content-Type: application/json"])

	refresh_http.request_completed.connect(func(result, code, _headers, body):
		_is_refreshing = false
		refresh_http.queue_free()

		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			print("リフレッシュ失敗 - ログアウト")
			UserDataManager.logout()
			request_failed.emit("セッションの更新に失敗しました。再度ログインしてください。")
			return

		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) != OK:
			UserDataManager.logout()
			request_failed.emit("リフレッシュレスポンスの解析に失敗しました")
			return

		var data = json.data
		if data.has("token"):
			var new_access = data["token"].get("access_token", "")
			var new_refresh = data["token"].get("refresh_token", "")
			if new_access != "":
				UserDataManager.update_tokens(new_access, new_refresh)
				print("トークンリフレッシュ成功 - 元のリクエストを再送")
				# 元のリクエストを再送
				var req = _pending_request
				if req.get("method") == "GET":
					get_request(req["endpoint"])
				elif req.get("method") == "POST":
					post_request(req["endpoint"], req["body"])
				return

		UserDataManager.logout()
		request_failed.emit("リフレッシュトークンが無効です")
	)

	refresh_http.request(refresh_url, refresh_headers, HTTPClient.METHOD_POST, refresh_body)
