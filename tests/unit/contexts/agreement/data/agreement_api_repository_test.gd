## AgreementApiRepository の単体テスト。偽の通信で、送る内容と応答の取り込みを確かめる。
extends GdUnitTestSuite

var _client: FakeApiClient
var _repository: AgreementApiRepository


func before_test() -> void:
	_client = auto_free(FakeApiClient.new())
	_client.configure(FakeApiClient.FakeAuth.new("tok", "ref"), null)
	_repository = AgreementApiRepository.new(_client)


## 前提: agreement_list が 1 件。操作: fetch_pending。
## 期待: GET /agreement/pending（冪等キー無し・本文無し）で、5 項目が型付きで取り込める。
func test_fetch_pending_parses_list() -> void:
	var item := {
		"sys_agreement_id": 1,
		"version": "1.0.0",
		"title": "利用規約",
		"url": "https://example.com/t",
		"published_at": "2026-01-01 00:00:00",
	}
	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(200, {"agreement_list": [item]})
	var result := await _repository.fetch_pending()

	assert_bool(result.ok).is_true()
	assert_int(result.agreements.size()).is_equal(1)
	assert_int(result.agreements[0].sys_agreement_id).is_equal(1)
	assert_str(result.agreements[0].title).is_equal("利用規約")
	var call: Dictionary = _client.calls[0]
	assert_str(call["method"]).is_equal("GET")
	assert_str(call["body"]).is_empty()
	var headers: PackedStringArray = call["headers"]
	assert_str(FakeApiClient.header_value(headers, "X-Unique-Request-Identifier")).is_empty()


## 前提: agreement_list が null / 欠落。期待: 空の一覧の成功（見せる規約が無い）。
func test_null_and_missing_list_are_empty() -> void:
	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(200, {"agreement_list": null})
	var with_null := await _repository.fetch_pending()
	assert_bool(with_null.ok).is_true()
	assert_array(with_null.agreements).is_empty()

	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, {})
	var missing := await _repository.fetch_pending()
	assert_bool(missing.ok).is_true()
	assert_array(missing.agreements).is_empty()


## 前提: 取得が 503 メンテナンス。期待: MAINTENANCE の失敗で返る。
func test_fetch_failure_becomes_error() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(503, {"title": "t"})
	var result := await _repository.fetch_pending()
	assert_int(result.error.kind).is_equal(AppError.Kind.MAINTENANCE)


## 前提: 200 の consent。操作: consent(3, "k")。
## 期待: POST /agreement/consent に sys_agreement_id と冪等キーを付けて送る。24002 は BUSINESS で返る。
func test_consent_sends_id_and_key() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, {})
	var result := await _repository.consent(3, "k")
	assert_bool(result.ok).is_true()
	var call: Dictionary = _client.calls[0]
	assert_str(call["url"]).ends_with("/agreement/consent")
	assert_int(int(JSON.parse_string(call["body"])["sys_agreement_id"])).is_equal(3)
	var headers: PackedStringArray = call["headers"]
	assert_str(FakeApiClient.header_value(headers, "X-Unique-Request-Identifier")).is_equal("k")

	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(299, {"error_code": 24002, "message": "m"})
	var consented := await _repository.consent(3, "k2")
	assert_int(consented.error.kind).is_equal(AppError.Kind.BUSINESS)
	assert_int(consented.error.error_code).is_equal(24002)


## 前提: サーバーの実際の成功応答（本文が空の配列 `[]`）。操作: consent。
## 期待: 成功になる（ApiClient が空の配列を空の辞書として受け、PARSE の失敗にしない）。
func test_consent_success_with_empty_array_body() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, "[]")
	var result := await _repository.consent(3, "k")
	assert_bool(result.ok).is_true()
