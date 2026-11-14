## ApiClient の X-Platform ヘッダーの単体テスト（client_design.md 5-1・5-3）。
## HTTP の送信は FakeApiClient が差し替えるので、実通信はしない。
extends GdUnitTestSuite

const OLD_TOKEN := "old-access"
const NEW_TOKEN := "new-access"

var _client: FakeApiClient
var _auth: FakeApiClient.FakeAuth
var _master_hash: FakeApiClient.FakeMasterHash


func before_test() -> void:
	_client = auto_free(FakeApiClient.new())
	_auth = FakeApiClient.FakeAuth.new(OLD_TOKEN, "old-refresh")
	_master_hash = FakeApiClient.FakeMasterHash.new("")
	_client.configure(_auth, _master_hash)


## 前提: platform を Google にして configure。操作: 認証あり・なし・GET の request。
## 期待: どれにも X-Platform が付く（version など除外ルートも一律）。
func test_request_sends_x_platform_on_every_request() -> void:
	_client.configure(_auth, _master_hash, "Google")
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, {})
	await _client.request("POST", "/x")
	await _client.request("GET", "/auth/version?deploy_version=0", {}, {"auth": false})
	for call in _client.calls:
		assert_str(FakeApiClient.header_value(call["headers"], "X-Platform")).is_equal("Google")


## 前提: 401 → refresh → 再送。期待: refresh の送信にも X-Platform が付く。
func test_refresh_request_sends_x_platform() -> void:
	_client.configure(_auth, _master_hash, "Apple")
	var counter := {"n": 0}
	_client.handler = func(_m, url, _h, _b):
		if str(url).ends_with("/auth/refresh_token"):
			return FakeApiClient.response(
				200, {"token": {"access_token": NEW_TOKEN, "refresh_token": "r2"}}
			)
		counter["n"] += 1
		return FakeApiClient.response(401 if counter["n"] == 1 else 200, {})
	await _client.request("POST", "/x")
	var refresh_calls := _client.calls.filter(
		func(c): return str(c["url"]).ends_with("/auth/refresh_token")
	)
	assert_int(refresh_calls.size()).is_equal(1)
	assert_str(FakeApiClient.header_value(refresh_calls[0]["headers"], "X-Platform")).is_equal(
		"Apple"
	)


## 前提: platform を空文字にする（set_platform("")）。期待: X-Platform を付けない（e2e の欠落の再現）。
func test_empty_platform_omits_header() -> void:
	_client.configure(_auth, _master_hash, "Apple")
	_client.set_platform("")
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, {})
	await _client.request("POST", "/x")
	assert_str(FakeApiClient.header_value(_client.calls[0]["headers"], "X-Platform")).is_empty()
	_client.set_platform("Google")
	await _client.request("POST", "/x")
	assert_str(FakeApiClient.header_value(_client.calls[1]["headers"], "X-Platform")).is_equal(
		"Google"
	)


## 前提: platform を設定済み。操作: download。期待: X-Platform を付けない（API ではない配信ホストへ送らない）。
func test_download_does_not_send_x_platform() -> void:
	_client.configure(_auth, _master_hash, "Apple")
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, "bytes")
	await _client.download("http://cdn.test/file")
	assert_str(FakeApiClient.header_value(_client.calls[0]["headers"], "X-Platform")).is_empty()


## 前提: 認証あり・なし・GET の request。期待: どれにも Accept-Language: ja が付く（言語は固定。
## X-Platform を空にしても付く＝付けない状態は作らない）。
func test_request_sends_accept_language_on_every_request() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, {})
	await _client.request("POST", "/x")
	await _client.request("GET", "/auth/version?deploy_version=0", {}, {"auth": false})
	_client.set_platform("")
	await _client.request("POST", "/x")
	assert_int(_client.calls.size()).is_equal(3)
	for call in _client.calls:
		assert_str(FakeApiClient.header_value(call["headers"], "Accept-Language")).is_equal("ja")


## 前提: 401 → refresh → 再送。期待: refresh の送信にも Accept-Language が付く。
func test_refresh_request_sends_accept_language() -> void:
	var counter := {"n": 0}
	_client.handler = func(_m, url, _h, _b):
		if str(url).ends_with("/auth/refresh_token"):
			return FakeApiClient.response(
				200, {"token": {"access_token": NEW_TOKEN, "refresh_token": "r2"}}
			)
		counter["n"] += 1
		return FakeApiClient.response(401 if counter["n"] == 1 else 200, {})
	await _client.request("POST", "/x")
	var refresh_calls := _client.calls.filter(
		func(c): return str(c["url"]).ends_with("/auth/refresh_token")
	)
	assert_int(refresh_calls.size()).is_equal(1)
	assert_str(FakeApiClient.header_value(refresh_calls[0]["headers"], "Accept-Language")).is_equal(
		"ja"
	)


## 前提: download（配信ホスト・規約本文）。期待: Accept-Language を付けない（API ではないホストへ送らない）。
func test_download_does_not_send_accept_language() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, "bytes")
	await _client.download("http://cdn.test/file")
	(
		assert_str(FakeApiClient.header_value(_client.calls[0]["headers"], "Accept-Language"))
		. is_empty()
	)
