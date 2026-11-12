## テスト用の ApiClient。HTTP の送信（_send_http）だけを差し替え、実通信をしない。
##
## 目的: ApiClient の分類・refresh・ヘッダー付与を、サーバーなしで検証する。
## 使い方:
##   1. handler に「(method, url, headers, body) -> response 辞書」の Callable を入れる
##      （await してよい。response 辞書は FakeApiClient.response() / network_error() で作る）
##   2. calls に、送られたリクエスト {method, url, headers, body} が順に溜まる
## ほかにテストが使う偽の契約実装（FakeAuth / FakeMasterHash）も同居させている。
class_name FakeApiClient
extends ApiClient

## 送られたリクエストの記録。{method, url, headers: PackedStringArray, body: String}
var calls: Array[Dictionary] = []
## 応答を決める関数。(method: String, url: String, headers: PackedStringArray, body: String) -> Dictionary
var handler: Callable = Callable()


## 実際の通信の代わりに、記録して handler の応答を返す。
func _send_http(
	method: String, url: String, headers: PackedStringArray, body: String, _timeout: float
) -> Dictionary:
	calls.append({"method": method, "url": url, "headers": headers, "body": body})
	if not handler.is_valid():
		return network_error()
	return await handler.call(method, url, headers, body)


## HTTP 応答の辞書を作る（_send_http の戻り値と同じ形）。body は JSON 文字列にする。
static func response(
	status: int, body: Variant = {}, headers: PackedStringArray = PackedStringArray()
) -> Dictionary:
	var text: String = body if body is String else JSON.stringify(body)
	return {
		"result": HTTPRequest.RESULT_SUCCESS,
		"status": status,
		"headers": headers,
		"body": text.to_utf8_buffer(),
	}


## 通信自体の失敗（接続不可・タイムアウトなど）。
static func network_error() -> Dictionary:
	return {
		"result": HTTPRequest.RESULT_CANT_CONNECT,
		"status": 0,
		"headers": PackedStringArray(),
		"body": PackedByteArray(),
	}


## 記録したリクエストのうち、url が endpoint で終わるものの数。
func count_calls(endpoint: String) -> int:
	var count := 0
	for call in calls:
		if str(call["url"]).ends_with(endpoint):
			count += 1
	return count


## ヘッダー配列から名前に一致する値を返す（無ければ空文字）。
static func header_value(headers: PackedStringArray, header_name: String) -> String:
	var prefix := header_name.to_lower() + ":"
	for header in headers:
		if header.to_lower().begins_with(prefix):
			return header.substr(prefix.length()).strip_edges()
	return ""


## 偽の認証トークン供給。保存された回数も数える。
class FakeAuth:
	extends ApiAuthProvider
	var access: String = ""
	var refresh: String = ""
	var save_count: int = 0

	func _init(p_access: String = "", p_refresh: String = "") -> void:
		access = p_access
		refresh = p_refresh

	func access_token() -> String:
		return access

	func refresh_token() -> String:
		return refresh

	func save_tokens(p_access: String, p_refresh: String) -> void:
		access = p_access
		refresh = p_refresh
		save_count += 1


## 偽のマスターハッシュ供給。
class FakeMasterHash:
	extends MasterHashProvider
	var value: String = ""

	func _init(p_value: String = "") -> void:
		value = p_value

	func master_hash() -> String:
		return value
