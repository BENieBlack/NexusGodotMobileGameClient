## LoginBonusCalendarApiRepository の単体テスト。偽の通信で、list は冪等キー無し・receive は冪等キーつきで
## 本文に mst_vip_login_bonus_id が入ること、失敗が AppError になることを確かめる（login_api_repository_test の方式）。
extends GdUnitTestSuite

var _client: FakeApiClient
var _repository: LoginBonusCalendarApiRepository


func before_test() -> void:
	_client = auto_free(FakeApiClient.new())
	_client.configure(FakeApiClient.FakeAuth.new("tok", "ref"), null)
	_repository = LoginBonusCalendarApiRepository.new(_client)


## 前提: 200 の list 応答。期待: POST /login_bonus/list・冪等キーのヘッダー無し・Authorization あり。
## 段が読める（旧キーが無くても失敗にならない）。
func test_list_has_no_idempotency_key() -> void:
	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(
			200, {"login_bonus_calendar": {"mst_login_bonus_id": "lb1", "last_received_day": 1}}
		)
	var result := await _repository.fetch_calendars()

	assert_bool(result.ok).is_true()
	assert_str(result.calendars.normal.mst_id).is_equal("lb1")
	assert_object(result.calendars.vip).is_null()
	var call: Dictionary = _client.calls[0]
	assert_str(call["method"]).is_equal("POST")
	assert_str(call["url"]).ends_with("/login_bonus/list")
	var headers: PackedStringArray = call["headers"]
	assert_str(FakeApiClient.header_value(headers, "X-Unique-Request-Identifier")).is_empty()
	assert_str(FakeApiClient.header_value(headers, "Authorization")).is_equal("Bearer tok")


## 前提: 200 の receive 応答。期待: POST /login_bonus/receive・冪等キーあり・本文に mst_vip_login_bonus_id。
func test_receive_sends_key_and_body() -> void:
	_client.handler = func(_m, _u, _h, _b):
		return (
			FakeApiClient
			. response(
				200,
				{
					"login_bonus_list": [{"type": "item", "id": "free_diamond", "amount": 10}],
					"vip_login_bonus_calendar":
					{"mst_vip_login_bonus_id": "vip5", "is_granted_now": true},
					"updated_resources": {},
				}
			)
		)
	var result := await _repository.receive_vip("vip5", "key-1")

	assert_bool(result.ok).is_true()
	assert_int(result.rewards.size()).is_equal(1)
	var call: Dictionary = _client.calls[0]
	assert_str(call["url"]).ends_with("/login_bonus/receive")
	var headers: PackedStringArray = call["headers"]
	assert_str(FakeApiClient.header_value(headers, "X-Unique-Request-Identifier")).is_equal("key-1")
	var body: Dictionary = JSON.parse_string(call["body"])
	assert_str(body["mst_vip_login_bonus_id"]).is_equal("vip5")


## 前提: 299（26001）・409・通信断。期待: BUSINESS・CONFLICT・NETWORK の AppError で返る（list・receive 両方）。
## BUSINESS だけ冪等キーを再利用できない（作り直す）。
func test_failures_become_app_errors() -> void:
	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(299, {"error_code": 26001, "message": "m"})
	var business := await _repository.receive_vip("vip5", "k")
	assert_bool(business.ok).is_false()
	assert_int(business.error.kind).is_equal(AppError.Kind.BUSINESS)
	assert_int(business.error.error_code).is_equal(26001)
	assert_bool(IdempotencyKey.can_reuse(business.error.kind)).is_false()

	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(409, {"error_code": 40900})
	var conflict := await _repository.receive_vip("vip5", "k")
	assert_int(conflict.error.kind).is_equal(AppError.Kind.CONFLICT)
	assert_bool(IdempotencyKey.can_reuse(conflict.error.kind)).is_true()

	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.network_error()
	var network := await _repository.fetch_calendars()
	assert_bool(network.ok).is_false()
	assert_int(network.error.kind).is_equal(AppError.Kind.NETWORK)
	assert_bool(IdempotencyKey.can_reuse(network.error.kind)).is_true()
