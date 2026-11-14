## LoginApiRepository の単体テスト。偽の通信で、冪等キーつきの送信と失敗の変換を確かめる。
extends GdUnitTestSuite

var _client: FakeApiClient
var _repository: LoginApiRepository


func before_test() -> void:
	_client = auto_free(FakeApiClient.new())
	_client.configure(FakeApiClient.FakeAuth.new("tok", "ref"), null)
	_repository = LoginApiRepository.new(_client)


## 前提: 200 の応答。操作: fetch_login("key-1")。
## 期待: POST /auth/login に冪等キー（D6）と Authorization が付き、応答が取り込まれる。
func test_sends_idempotency_key_and_parses() -> void:
	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(200, {"sys_player": {"my_id": "abc"}})
	var result := await _repository.fetch_login("key-1")

	assert_bool(result.ok).is_true()
	assert_str(str(result.sys_player["my_id"])).is_equal("abc")
	var call: Dictionary = _client.calls[0]
	assert_str(call["method"]).is_equal("POST")
	assert_str(call["url"]).ends_with("/auth/login")
	var headers: PackedStringArray = call["headers"]
	assert_str(FakeApiClient.header_value(headers, "X-Unique-Request-Identifier")).is_equal("key-1")
	assert_str(FakeApiClient.header_value(headers, "Authorization")).is_equal("Bearer tok")


## 前提: 409 / 299。操作: fetch_login。期待: CONFLICT / BUSINESS の AppError で返る。
func test_failures_are_returned_as_errors() -> void:
	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(409, {"error_code": 40900})
	assert_int((await _repository.fetch_login("k")).error.kind).is_equal(AppError.Kind.CONFLICT)

	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(299, {"error_code": 99999, "message": "m"})
	var business := await _repository.fetch_login("k")
	assert_int(business.error.kind).is_equal(AppError.Kind.BUSINESS)
	assert_int(business.error.error_code).is_equal(99999)


## 前提: 200 で本文が `[]`（プロキシなどの空の応答を想定）。操作: fetch_login。
## 期待: PARSE の失敗（成功扱いにすると player とログインボーナスが空で置き換わる）。
func test_empty_array_body_is_parse_error() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, "[]")
	var result := await _repository.fetch_login("k")
	assert_bool(result.ok).is_false()
	assert_int(result.error.kind).is_equal(AppError.Kind.PARSE)


## 固定の時刻を返す偽の Clock。
class FixedClock:
	extends Clock
	var value: int = 0

	func _init(p_value: int) -> void:
		value = p_value

	func now_unix() -> int:
		return value


## 前提: 応答に Date ヘッダー（1794621799）があり、端末が 1 時間進んでいる。
## 期待: offset = サーバー時刻 − 端末時刻 = -3600、has_server_time が真。trx_diamond も取り込む。
func test_date_header_makes_server_time_offset() -> void:
	var repository := LoginApiRepository.new(_client, FixedClock.new(1794621799 + 3600))
	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(
			200,
			{"sys_player": {"my_id": "a"}, "trx_diamond": {"paid_amount": 7}},
			PackedStringArray(["date: Sat, 14 Nov 2026 02:03:19 GMT"])
		)
	var result := await repository.fetch_login("k")
	assert_bool(result.has_server_time).is_true()
	assert_int(result.server_time_offset_seconds).is_equal(-3600)
	assert_int(int(result.trx_diamond["paid_amount"])).is_equal(7)


## 前提: Date が無い・読めない応答。期待: 成功のまま、has_server_time が偽・offset 0（端末時計のみ）。
func test_missing_or_invalid_date_falls_back_to_device_clock() -> void:
	var repository := LoginApiRepository.new(_client, FixedClock.new(1000))
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, {})
	var no_date := await repository.fetch_login("k")
	assert_bool(no_date.ok).is_true()
	assert_bool(no_date.has_server_time).is_false()
	assert_int(no_date.server_time_offset_seconds).is_equal(0)

	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(200, {}, PackedStringArray(["Date: not a date"]))
	var bad_date := await repository.fetch_login("k")
	assert_bool(bad_date.ok).is_true()
	assert_bool(bad_date.has_server_time).is_false()
	assert_int(bad_date.server_time_offset_seconds).is_equal(0)
