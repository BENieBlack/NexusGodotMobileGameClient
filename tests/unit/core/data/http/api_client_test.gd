## ApiClient の単体テスト（client_design.md 3-5）: 分類・ヘッダー・更新要求・ダウンロード。
## 401 の refresh と冪等キーは api_client_refresh_test.gd。
##
## HTTP の送信は FakeApiClient が差し替えるので、実通信はしない。
## 構成: 1. X-Master-Update-Required の判定（旧 scripts/tests/master_hash_test.gd から移した）
##       2. 失敗の分類  3. ヘッダーの付与  4. X-Master-Update-Required のシグナル  7. ダウンロード
extends GdUnitTestSuite

const OLD_TOKEN := "old-access"
const NEW_TOKEN := "new-access"

var _client: FakeApiClient
var _auth: FakeApiClient.FakeAuth
var _master_hash: FakeApiClient.FakeMasterHash


## テストごとに、偽の通信と偽の契約実装をつないだ ApiClient を作る。
func before_test() -> void:
	_client = auto_free(FakeApiClient.new())
	_auth = FakeApiClient.FakeAuth.new(OLD_TOKEN, "old-refresh")
	_master_hash = FakeApiClient.FakeMasterHash.new("")
	_client.configure(_auth, _master_hash)


# --- 1. X-Master-Update-Required の判定 ---


## 前提: ヘッダー配列。操作: has_master_update_required。
## 期待: true / 1 は大文字小文字を区別せず真、false・無しは偽。
## サーバーが 200 応答に付けるこのヘッダーの取りこぼしと誤検出を守る（旧 master_hash_test の期待）。
func test_has_master_update_required() -> void:
	(
		assert_bool(
			ApiClient.has_master_update_required(
				PackedStringArray(
					["Content-Type: application/json", "X-Master-Update-Required: true"]
				)
			)
		)
		. is_true()
	)
	(
		assert_bool(
			ApiClient.has_master_update_required(PackedStringArray(["x-master-update-required: 1"]))
		)
		. is_true()
	)
	(
		assert_bool(
			ApiClient.has_master_update_required(
				PackedStringArray(["X-Master-Update-Required: false"])
			)
		)
		. is_false()
	)
	(
		assert_bool(
			ApiClient.has_master_update_required(
				PackedStringArray(["Content-Type: application/json"])
			)
		)
		. is_false()
	)


# --- 2. 失敗の分類 ---


## 前提: 200 + JSON。操作: request。期待: ok で data が読める。
func test_success_returns_data() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, {"a": 1})
	var result := await _client.request("GET", "/x")
	assert_bool(result.ok).is_true()
	assert_int(result.http_status).is_equal(200)
	assert_int(int(result.data["a"])).is_equal(1)


## 前提: 通信自体が失敗。操作: request。期待: NETWORK。
func test_network_failure() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.network_error()
	var result := await _client.request("GET", "/x")
	assert_bool(result.ok).is_false()
	assert_int(result.kind).is_equal(AppError.Kind.NETWORK)


## 前提: 各 HTTP ステータスと本文。操作: request（認証なし）。期待: 設計 3-5 の表のとおりの種別。
## 401・429・503（メンテ）は error_code を持たず、HTTP ステータスで分類する必要がある（D5）。
## 299 だけが error_code を読む。どれかが入れ替わると、画面の文言と動線が変わる。
func test_status_classification() -> void:
	var cases := [
		[429, {"error": "TOO_MANY_REQUESTS", "retry_after": 30}, AppError.Kind.RATE_LIMITED],
		[503, {"title": "t", "message": "m"}, AppError.Kind.MAINTENANCE],
		[503, {"error_code": 50300, "message": "m"}, AppError.Kind.SERVER_BUSY],
		[409, {"error_code": 40900}, AppError.Kind.CONFLICT],
		[299, {"error_code": 10002, "message": "m"}, AppError.Kind.BUSINESS],
		[422, {"message": "m"}, AppError.Kind.VALIDATION],
		[500, {"error_code": 500, "message": "m"}, AppError.Kind.SERVER_ERROR],
		[404, "not json", AppError.Kind.SERVER_ERROR],
		[401, {"error": "INVALID_SIGNATURE"}, AppError.Kind.SIGNATURE],
	]
	for case in cases:
		var captured_status: int = case[0]
		var captured_body: Variant = case[1]
		_client.handler = func(_m, _u, _h, _b):
			return FakeApiClient.response(captured_status, captured_body)
		var result := await _client.request("POST", "/x", {}, {"auth": false})
		assert_bool(result.ok).is_false()
		assert_int(result.kind).is_equal(case[2])


## 前提: 429 に retry_after、503 にメンテ情報、299 に error_code。操作: request して AppError に直す。
## 期待: 付帯情報（retry_after / maintenance / error_code）が AppError に載る。
func test_extra_info_is_carried_to_app_error() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(429, {"retry_after": 42})
	var rate := (await _client.request("GET", "/x", {}, {"auth": false})).to_app_error()
	assert_int(rate.retry_after).is_equal(42)

	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(503, {"title": "T", "message": "M", "end_at": "2026-01-01"})
	var maintenance := (await _client.request("GET", "/x", {}, {"auth": false})).to_app_error()
	assert_str(str(maintenance.maintenance["title"])).is_equal("T")
	assert_str(str(maintenance.maintenance["end_at"])).is_equal("2026-01-01")

	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(299, {"error_code": 10004, "message": "dup"})
	var business := (await _client.request("POST", "/x", {}, {"auth": false})).to_app_error()
	assert_int(business.error_code).is_equal(10004)
	assert_str(business.message).is_equal("dup")


## 前提: 200 だが本文が JSON でない / 299 だが本文が読めない。操作: request。期待: PARSE。
func test_unparsable_body_is_parse_error() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, "<html>")
	assert_int((await _client.request("GET", "/x")).kind).is_equal(AppError.Kind.PARSE)
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(299, "<html>")
	assert_int((await _client.request("GET", "/x")).kind).is_equal(AppError.Kind.PARSE)


# --- 3. ヘッダーの付与 ---


## 前提: トークンと master_hash がある。操作: 認証付きで request。
## 期待: Authorization と X-Master-Hash が付く。認証なし（auth=false）では Authorization が付かない。
## 全 API に X-Master-Hash を付ける（旧実装は sign_up / sign_in / refresh に付いていなかった。設計 3-5）。
func test_auth_and_master_hash_headers() -> void:
	_master_hash.value = "hash-1"
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200)
	await _client.request("GET", "/x")
	var headers: PackedStringArray = _client.calls[0]["headers"]
	assert_str(FakeApiClient.header_value(headers, "Authorization")).is_equal("Bearer " + OLD_TOKEN)
	assert_str(FakeApiClient.header_value(headers, "X-Master-Hash")).is_equal("hash-1")

	await _client.request("GET", "/y", {}, {"auth": false})
	var no_auth_headers: PackedStringArray = _client.calls[1]["headers"]
	assert_str(FakeApiClient.header_value(no_auth_headers, "Authorization")).is_empty()
	assert_str(FakeApiClient.header_value(no_auth_headers, "X-Master-Hash")).is_equal("hash-1")


## 前提: master_hash が空（初回）。操作: request。期待: X-Master-Hash を付けない。
## 空のヘッダーを送ると、サーバーが「不一致」と見て更新要求を返しうるため。
func test_empty_master_hash_is_not_sent() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200)
	await _client.request("GET", "/x")
	var headers: PackedStringArray = _client.calls[0]["headers"]
	assert_str(FakeApiClient.header_value(headers, "X-Master-Hash")).is_empty()


## 前提: GET と POST。操作: request。期待: GET は本文なし、POST は JSON の本文、URL は ApiConfig のベース + endpoint。
func test_method_body_and_url() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200)
	await _client.request("GET", "/x?a=1")
	await _client.request("POST", "/y", {"k": "v"})
	assert_str(_client.calls[0]["body"]).is_empty()
	assert_str(_client.calls[0]["url"]).is_equal(ApiConfig.api_base_url() + "/x?a=1")
	assert_str(_client.calls[1]["method"]).is_equal("POST")
	assert_str(_client.calls[1]["body"]).is_equal('{"k":"v"}')


# --- 4. X-Master-Update-Required ---


## 前提: 200 の応答に X-Master-Update-Required: true。操作: request。
## 期待: master_update_required が 1 回出て、結果は待たずに ok で返る。
func test_master_update_required_signal_on_200() -> void:
	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(
			200, {}, PackedStringArray(["X-Master-Update-Required: true"])
		)
	var counter := [0]
	_client.master_update_required.connect(func(): counter[0] += 1)
	var result := await _client.request("GET", "/x")
	assert_bool(result.ok).is_true()
	assert_int(counter[0]).is_equal(1)


## 前提: ヘッダー付きだが 299 / version API の 200。操作: request。期待: シグナルは出ない。
## サーバーは 200 にだけ付ける仕様で、version 自体は本文の needs_update で足りるため（設計 3-5）。
func test_master_update_required_ignored_for_299_and_version() -> void:
	var counter := [0]
	_client.master_update_required.connect(func(): counter[0] += 1)
	var headers := PackedStringArray(["X-Master-Update-Required: true"])
	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(299, {"error_code": 1}, headers)
	await _client.request("POST", "/x")
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, {}, headers)
	await _client.request("GET", "/auth/version?deploy_version=0", {}, {"auth": false})
	assert_int(counter[0]).is_equal(0)


# --- 7. ダウンロード ---


## 前提: 配信ホストが 200 でバイト列 / 404 / 通信断を返す。操作: download。
## 期待: 200 なら raw_body にバイト列、404 は SERVER_ERROR、通信断は NETWORK。認証ヘッダーは付けない。
func test_download() -> void:
	_client.handler = func(_m, _u, _h, _b):
		return {
			"result": HTTPRequest.RESULT_SUCCESS,
			"status": 200,
			"headers": PackedStringArray(),
			"body": PackedByteArray([1, 2, 3]),
		}
	var ok := await _client.download("http://cdn.test/f.sqlite")
	assert_bool(ok.ok).is_true()
	assert_array(ok.raw_body).contains_exactly([1, 2, 3])
	var sent_headers: PackedStringArray = _client.calls[0]["headers"]
	assert_str(FakeApiClient.header_value(sent_headers, "Authorization")).is_empty()

	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(404)
	assert_int((await _client.download("http://cdn.test/f")).kind).is_equal(
		AppError.Kind.SERVER_ERROR
	)
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.network_error()
	assert_int((await _client.download("http://cdn.test/f")).kind).is_equal(AppError.Kind.NETWORK)
