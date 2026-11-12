## ApiClient の単体テスト（client_design.md 3-4・3-5）: 401 の refresh と冪等キー。
## 分類・ヘッダー・更新要求・ダウンロードは api_client_test.gd。
##
## HTTP の送信は FakeApiClient が差し替えるので、実通信はしない。
## 構成: 5. 401 の refresh（1 本化・再送 1 回・セッション破棄）  6. 冪等キー
extends GdUnitTestSuite

const OLD_TOKEN := "old-access"
const NEW_TOKEN := "new-access"

var _client: FakeApiClient
var _auth: FakeApiClient.FakeAuth


## テストごとに、偽の通信と偽の認証供給をつないだ ApiClient を作る。
func before_test() -> void:
	_client = auto_free(FakeApiClient.new())
	_auth = FakeApiClient.FakeAuth.new(OLD_TOKEN, "old-refresh")
	_client.configure(_auth, FakeApiClient.FakeMasterHash.new(""))


# --- 5. 401 の refresh ---


## 古いトークンなら 401、新しいトークンなら 200、refresh は新しいトークンを返す応答関数。
## refresh_status / refresh_body で refresh の応答を変えられる。
func _refreshing_handler(refresh_status: int = 200, refresh_body: Variant = null) -> Callable:
	var body: Variant = refresh_body
	if body == null:
		body = {"token": {"access_token": NEW_TOKEN, "refresh_token": "new-refresh"}}
	return func(_m: String, url: String, headers: PackedStringArray, _b: String) -> Dictionary:
		# 並行 401 を再現するため、1 フレーム待ってから応答する（複数の呼び出しが同時に飛ぶ状態にする）
		await Engine.get_main_loop().process_frame
		if url.ends_with("/auth/refresh_token"):
			return FakeApiClient.response(refresh_status, body)
		if FakeApiClient.header_value(headers, "Authorization") == "Bearer " + NEW_TOKEN:
			return FakeApiClient.response(200, {"ok": true})
		return FakeApiClient.response(401, {"error": "Invalid or expired access token"})


## 前提: アクセストークンが期限切れ。操作: request。
## 期待: refresh を 1 回呼び、トークンを保存し、同じリクエストを新しいトークンで再送して成功する。
func test_401_refreshes_and_retries_once() -> void:
	_client.handler = _refreshing_handler()
	var result := await _client.request("GET", "/x")
	assert_bool(result.ok).is_true()
	assert_int(_client.count_calls("/auth/refresh_token")).is_equal(1)
	assert_int(_client.count_calls("/x")).is_equal(2)
	assert_str(_auth.access).is_equal(NEW_TOKEN)
	assert_str(_auth.refresh).is_equal("new-refresh")
	assert_int(_auth.save_count).is_equal(1)


## 前提: 同時に 3 本のリクエストが全部 401。操作: 並行して request。
## 期待: refresh は 1 回だけ。3 本とも新しいトークンで 1 回ずつ再送して成功する。
## refresh は 429（15 分 10 回）の対象で、同じ refresh_token の同時送信は 10003 になるため 1 本にまとめる。
func test_concurrent_401_share_one_refresh() -> void:
	_client.handler = _refreshing_handler()
	var results := {}
	_start_request(results, "a", "/a")
	_start_request(results, "b", "/b")
	_start_request(results, "c", "/c")
	await _wait_for(results, 3)
	for key in ["a", "b", "c"]:
		assert_bool(results[key].ok).is_true()
	assert_int(_client.count_calls("/auth/refresh_token")).is_equal(1)
	assert_int(_client.count_calls("/a")).is_equal(2)
	assert_int(_client.count_calls("/b")).is_equal(2)
	assert_int(_client.count_calls("/c")).is_equal(2)


## 前提: 送信中に他のリクエストが refresh を済ませた（トークンが変わった）後で 401 が返る。操作: request。
## 期待: 再 refresh せず、新しいトークンで再送だけする。
## 同じ refresh_token で 2 回目を送ると 10003 になり、不要にセッションを失うため。
func test_401_after_someone_else_refreshed_resends_without_refresh() -> void:
	var first := [true]
	_client.handler = func(
		_m: String, url: String, headers: PackedStringArray, _b: String
	) -> Dictionary:
		if url.ends_with("/auth/refresh_token"):
			return FakeApiClient.response(200, {"token": {"access_token": "never"}})
		if first[0]:
			# 最初の送信が 401 で返る間に、別のところで refresh が済んだ状態を作る
			first[0] = false
			_auth.access = NEW_TOKEN
			return FakeApiClient.response(401)
		return FakeApiClient.response(200, {"ok": true})
	var result := await _client.request("GET", "/x")
	assert_bool(result.ok).is_true()
	assert_int(_client.count_calls("/auth/refresh_token")).is_equal(0)
	assert_int(_client.count_calls("/x")).is_equal(2)


## 前提: refresh は成功するが、再送もずっと 401。操作: request。
## 期待: refresh は 1 回で打ち切り（ループしない）、SESSION_EXPIRED を返し、session_expired が出る。
## 旧実装は再送の 401 でまた refresh し、上限が無かった（設計 0 節 g）。
func test_second_401_stops_with_session_expired() -> void:
	_client.handler = func(
		_m: String, url: String, _h: PackedStringArray, _b: String
	) -> Dictionary:
		if url.ends_with("/auth/refresh_token"):
			return FakeApiClient.response(
				200, {"token": {"access_token": NEW_TOKEN, "refresh_token": "r"}}
			)
		return FakeApiClient.response(401)
	var expired := [0]
	_client.session_expired.connect(func(): expired[0] += 1)
	var result := await _client.request("GET", "/x")
	assert_int(result.kind).is_equal(AppError.Kind.SESSION_EXPIRED)
	assert_int(_client.count_calls("/auth/refresh_token")).is_equal(1)
	assert_int(_client.count_calls("/x")).is_equal(2)
	assert_int(expired[0]).is_equal(1)


## 前提: refresh が失敗する各ケース（299 の 10003・299 の 10002・HTTP 500・本文が JSON でない・access_token が空）。
## 操作: request。期待: SESSION_EXPIRED、session_expired が 1 回出る、元のリクエストは再送しない。
## これらはすべて「セッション破棄」（D9）。1 つでも漏れると、無効なトークンのまま画面が進んでしまう。
func test_refresh_failures_expire_the_session() -> void:
	var cases := [
		[299, {"error_code": 10003, "message": "x"}],
		[299, {"error_code": 10002, "message": "x"}],
		[500, {"message": "x"}],
		[200, "<html>"],
		[200, {"token": {"access_token": ""}}],
	]
	for case in cases:
		_client.calls.clear()
		_client.handler = _refreshing_handler(case[0], case[1])
		var expired := [0]
		var on_expired := func(): expired[0] += 1
		_client.session_expired.connect(on_expired)
		var result := await _client.request("GET", "/x")
		_client.session_expired.disconnect(on_expired)
		assert_int(result.kind).is_equal(AppError.Kind.SESSION_EXPIRED)
		assert_int(expired[0]).is_equal(1)
		assert_int(_client.count_calls("/x")).is_equal(1)


## 前提: 同時に 3 本のリクエストが 401 になり、refresh が失敗する（299 の 10003）。操作: 並行して request。
## 期待: refresh は 1 回、session_expired は 1 回だけ（待機中の呼び出しは同じ失敗を共有し、
##   それぞれが emit しない）、3 本とも SESSION_EXPIRED。元のリクエストは再送しない。
## emit が呼び出しの数だけ出ると、受け手（auth など）の破棄処理が重複して走る。
func test_concurrent_401_with_failed_refresh_expires_once() -> void:
	_client.handler = _refreshing_handler(299, {"error_code": 10003, "message": "x"})
	var expired := [0]
	_client.session_expired.connect(func(): expired[0] += 1)
	var results := {}
	_start_request(results, "a", "/a")
	_start_request(results, "b", "/b")
	_start_request(results, "c", "/c")
	await _wait_for(results, 3)
	for key in ["a", "b", "c"]:
		assert_int(results[key].kind).is_equal(AppError.Kind.SESSION_EXPIRED)
	assert_int(_client.count_calls("/auth/refresh_token")).is_equal(1)
	assert_int(expired[0]).is_equal(1)
	assert_int(_client.count_calls("/a")).is_equal(1)


## 前提: refresh_token が空。操作: 401 を受ける request。期待: refresh を送らずに SESSION_EXPIRED。
func test_empty_refresh_token_expires_without_calling_api() -> void:
	_auth.refresh = ""
	_client.handler = _refreshing_handler()
	var result := await _client.request("GET", "/x")
	assert_int(result.kind).is_equal(AppError.Kind.SESSION_EXPIRED)
	assert_int(_client.count_calls("/auth/refresh_token")).is_equal(0)


## 前提: refresh が「試せなかった」失敗（通信断・429・503 メンテ・503 基盤不達）。操作: request。
## 期待: その失敗の種別をそのまま返し、セッションは破棄しない（session_expired を出さない）。
## ネットワーク断でログアウトさせると、電車の中でアカウントを失うため（設計 3-5）。
func test_refresh_that_could_not_be_tried_keeps_the_session() -> void:
	var cases := [
		[0, null, AppError.Kind.NETWORK],
		[429, {"retry_after": 5}, AppError.Kind.RATE_LIMITED],
		[503, {"title": "t"}, AppError.Kind.MAINTENANCE],
		[503, {"error_code": 50300}, AppError.Kind.SERVER_BUSY],
	]
	for case in cases:
		var status: int = case[0]
		var body: Variant = case[1]
		_client.handler = func(
			_m: String, url: String, _h: PackedStringArray, _b: String
		) -> Dictionary:
			if not url.ends_with("/auth/refresh_token"):
				return FakeApiClient.response(401)
			return (
				FakeApiClient.network_error()
				if status == 0
				else FakeApiClient.response(status, body)
			)
		var expired := [0]
		var on_expired := func(): expired[0] += 1
		_client.session_expired.connect(on_expired)
		var result := await _client.request("GET", "/x")
		_client.session_expired.disconnect(on_expired)
		assert_int(result.kind).is_equal(case[2])
		assert_int(expired[0]).is_equal(0)


## 前提: 認証なし（auth=false）のリクエストが 401。操作: request。
## 期待: refresh せず SIGNATURE（sign_up の署名不正）として返す。
func test_401_without_auth_does_not_refresh() -> void:
	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(401, {"error": "REQUEST_EXPIRED"})
	var result := await _client.request("POST", "/auth/sign_up", {}, {"auth": false})
	assert_int(result.kind).is_equal(AppError.Kind.SIGNATURE)
	assert_str(result.error_name).is_equal("REQUEST_EXPIRED")
	assert_int(_client.count_calls("/auth/refresh_token")).is_equal(0)


# --- 6. 冪等キー ---


## 前提: 冪等キーを options に渡す。操作: request。期待: X-Unique-Request-Identifier に載る。
## キーを渡さないときは付けない（GET・認証前 API には付けない。設計 3-4）。
func test_idempotency_header_is_sent_only_when_given() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200)
	await _client.request("POST", "/auth/login", {}, {"idempotency_key": "key-1"})
	await _client.request("GET", "/x")
	var with_key: PackedStringArray = _client.calls[0]["headers"]
	var without_key: PackedStringArray = _client.calls[1]["headers"]
	assert_str(FakeApiClient.header_value(with_key, "X-Unique-Request-Identifier")).is_equal(
		"key-1"
	)
	assert_str(FakeApiClient.header_value(without_key, "X-Unique-Request-Identifier")).is_empty()


## 前提: 401 → refresh → 再送になる POST。操作: 冪等キー付きで request。
## 期待: 1 回目と再送で同じキーが送られる（401 は冪等より手前で返り保存されないので再利用してよい。3-4）。
## キーが変わると、処理済みの二重実行を防げなくなる。
func test_idempotency_key_is_reused_on_resend_after_refresh() -> void:
	_client.handler = _refreshing_handler()
	await _client.request("POST", "/auth/login", {}, {"idempotency_key": "key-1"})
	var sent: Array[PackedStringArray] = []
	for call in _client.calls:
		if str(call["url"]).ends_with("/auth/login"):
			sent.append(call["headers"])
	assert_int(sent.size()).is_equal(2)
	assert_str(FakeApiClient.header_value(sent[0], "X-Unique-Request-Identifier")).is_equal("key-1")
	assert_str(FakeApiClient.header_value(sent[1], "X-Unique-Request-Identifier")).is_equal("key-1")


# --- 補助 ---


## request を待たずに開始し、完了したら results[key] に入れる（並行実行の再現用）。
func _start_request(results: Dictionary, key: String, endpoint: String) -> void:
	results[key] = await _client.request("GET", endpoint)


## results が count 件になるまで、フレームを進めて待つ（上限 200 フレーム。無限待ちを避ける）。
func _wait_for(results: Dictionary, count: int) -> void:
	for i in range(200):
		if results.size() >= count:
			return
		await Engine.get_main_loop().process_frame
