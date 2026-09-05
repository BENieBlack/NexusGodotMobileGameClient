extends Node

# 認証サービス - サインアップとサインインを管理
const BASE_URL = "http://localhost:8090/api/auth"

# クライアントシークレット（本番環境では暗号化または難読化が必要）
const CLIENT_SECRET = "your-secret-key-change-in-production-12345"

signal auth_completed(access_token: String, refresh_token: String, user_data: Dictionary)
signal auth_failed(error: String)

var http_request: HTTPRequest

func _ready():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

# UUIDv4を生成
func _generate_uuid() -> String:
	var random_bytes = []
	for i in range(16):
		random_bytes.append(randi() % 256)
	
	# UUID v4フォーマット（xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx）
	# バージョン4（ランダム）とバリアント（RFC 4122）を設定
	random_bytes[6] = (random_bytes[6] & 0x0F) | 0x40  # バージョン4
	random_bytes[8] = (random_bytes[8] & 0x3F) | 0x80  # バリアント
	
	var uuid = ""
	for i in range(16):
		if i == 4 or i == 6 or i == 8 or i == 10:
			uuid += "-"
		uuid += "%02x" % random_bytes[i]
	
	return uuid

# デバイスIDをリセット（新しいUUIDを生成）
func reset_device_id() -> void:
	var save_path = "user://device_id.save"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
		print("デバイスIDファイルを削除しました")
	else:
		print("デバイスIDファイルが存在しません")

# デバイス情報を取得
func _get_device_info() -> Dictionary:
	return {
		"os": OS.get_name(),
		"os_version": OS.get_version(),
		"model": OS.get_model_name(),
		"app_version": "1.0.0"
	}

# ランダムなノンスを生成（32文字）
func _generate_nonce() -> String:
	var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var nonce = ""
	for i in range(32):
		nonce += chars[randi() % chars.length()]
	return nonce

# HMAC-SHA256署名を生成
func _generate_signature(timestamp: String, nonce: String, body: String) -> String:
	var message = timestamp + ":" + nonce + ":" + body
	var key = CLIENT_SECRET.to_utf8_buffer()
	var data = message.to_utf8_buffer()
	
	# HMAC-SHA256を計算
	var signature = _hmac_sha256(key, data)
	
	# バイト配列を16進数文字列に変換
	var hex_string = ""
	for byte in signature:
		hex_string += "%02x" % byte
	
	return hex_string

# HMAC-SHA256実装
func _hmac_sha256(key: PackedByteArray, message: PackedByteArray) -> PackedByteArray:
	const BLOCK_SIZE = 64  # SHA-256のブロックサイズ
	
	# キーがブロックサイズより大きい場合はハッシュ化
	var processed_key = key
	if key.size() > BLOCK_SIZE:
		var ctx = HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(key)
		processed_key = ctx.finish()
	
	# キーをブロックサイズに調整（パディング）
	if processed_key.size() < BLOCK_SIZE:
		processed_key.resize(BLOCK_SIZE)
	
	# ipad と opad を作成
	var ipad = PackedByteArray()
	var opad = PackedByteArray()
	ipad.resize(BLOCK_SIZE)
	opad.resize(BLOCK_SIZE)
	
	for i in range(BLOCK_SIZE):
		ipad[i] = processed_key[i] ^ 0x36
		opad[i] = processed_key[i] ^ 0x5c
	
	# 内側のハッシュ: H((K ⊕ ipad) || message)
	var inner_ctx = HashingContext.new()
	inner_ctx.start(HashingContext.HASH_SHA256)
	inner_ctx.update(ipad)
	inner_ctx.update(message)
	var inner_hash = inner_ctx.finish()
	
	# 外側のハッシュ: H((K ⊕ opad) || inner_hash)
	var outer_ctx = HashingContext.new()
	outer_ctx.start(HashingContext.HASH_SHA256)
	outer_ctx.update(opad)
	outer_ctx.update(inner_hash)
	return outer_ctx.finish()

# 署名付きヘッダーを生成
func _create_signed_headers(body: String) -> PackedStringArray:
	var unix_time_float := Time.get_unix_time_from_system() as float
	var unix_time_int := int(unix_time_float) as int
	var timestamp := str(unix_time_int) as String
	var nonce := _generate_nonce() as String
	var signature := _generate_signature(timestamp, nonce, body) as String
	
	var header_array := PackedStringArray([
		"Content-Type: application/json",
		"X-Client-Timestamp: " + timestamp,
		"X-Client-Nonce: " + nonce,
		"X-Client-Signature: " + signature
	])
	
	return header_array

# デバイスIDを取得または生成
func _get_or_create_device_id() -> String:
	var save_path = "user://device_id.save"
	
	# 既にデバイスIDが保存されていれば返す
	if FileAccess.file_exists(save_path):
		var file = FileAccess.open(save_path, FileAccess.READ)
		if file:
			var device_id = file.get_as_text()
			file.close()
			print("既存のデバイスIDを使用: ", device_id)
			return device_id
	
	# 新しいUUIDベースのデバイスIDを生成
	var device_id = _generate_uuid()
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(device_id)
		file.close()
		print("新しいデバイスIDを生成: ", device_id)
	
	return device_id

# サインアップ（新規ユーザー登録）
func sign_up() -> void:
	var url = BASE_URL + "/sign_up"
	var body_dict = {
		"device_id": _get_or_create_device_id(),
		"device_info": _get_device_info()
	}
	var body = JSON.stringify(body_dict)
	var headers = _create_signed_headers(body)
	
	print("サインアップリクエスト送信: ", url)
	print("リクエストボディ: ", body)
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		auth_failed.emit("HTTPリクエストの作成に失敗しました")

# サインイン（既存ユーザーログイン）
func sign_in() -> void:
	var url = BASE_URL + "/sign_in"
	var body_dict = {
		"device_id": _get_or_create_device_id(),
		"device_info": _get_device_info()
	}
	var body = JSON.stringify(body_dict)
	var headers = PackedStringArray([
		"Content-Type: application/json"
	])
	
	print("サインインリクエスト送信: ", url)
	print("リクエストボディ: ", body)
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		auth_failed.emit("HTTPリクエストの作成に失敗しました")

# HTTPリクエスト完了時のコールバック
func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		print("リクエストエラー: ", result)
		auth_failed.emit("ネットワークエラーが発生しました")
		return

	var body_string = body.get_string_from_utf8()
	print("レスポンスコード: ", response_code)
	print("レスポンスボディ: ", body_string)

	var json = JSON.new()
	if json.parse(body_string) != OK:
		print("JSONパースエラー")
		auth_failed.emit("レスポンスの解析に失敗しました")
		return

	var response_data = json.data

	# HTTP 299: サーバ独自のビジネスロジックエラー
	if response_code == 299:
		var error_code = response_data.get("error_code", -1)
		var message = response_data.get("message", "不明なエラー")
		print("ビジネスエラー (", error_code, "): ", message)

		# error_code 10002: デバイスIDがサーバに存在しない → sign_upにフォールバック
		if error_code == 10002:
			print("デバイスIDがサーバに未登録 - 新規登録にフォールバック")
			# 保存済みのデバイスIDは再利用し、sign_upで登録し直す
			sign_up()
		else:
			auth_failed.emit("認証エラー: " + message)
		return

	if response_code != 200:
		print("サーバーエラー: ", response_code)
		auth_failed.emit("サーバーエラー: " + str(response_code))
		return

	print("認証成功: ", response_data)

	# サーバレスポンス: { "token": { "access_token": ..., "refresh_token": ..., "expires_in": ... }, "sys_player": {...}, ... }
	if response_data.has("token"):
		var token_data = response_data.get("token")
		var access_token = token_data.get("access_token", "")
		var refresh_token = token_data.get("refresh_token", "")

		var user_data = {}
		if response_data.has("sys_player"):
			user_data = response_data.get("sys_player")

		if access_token != "":
			auth_completed.emit(access_token, refresh_token, user_data)
		else:
			auth_failed.emit("トークンが取得できませんでした")
	else:
		auth_failed.emit("トークン情報が見つかりません (レスポンス: " + str(response_data.keys()) + ")")
