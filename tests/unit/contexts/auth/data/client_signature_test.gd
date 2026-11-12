## ClientSignature の単体テスト（サーバー api.md の署名の規則）。
extends GdUnitTestSuite


## 前提: 鍵 "test-secret"、timestamp / nonce / body が既知。操作: compute_signature。
## 期待: 別実装（Python の hmac / hashlib）で求めた HMAC-SHA256 の 16 進と一致する。
## 規則（"{timestamp}:{nonce}:{body}"、鍵、16 進小文字）が実装とサーバーでずれないことを守る。
func test_signature_matches_known_vector() -> void:
	var signature := ClientSignature.compute_signature(
		"1700000000", "abcdef", '{"device_id":"d"}', "test-secret"
	)
	assert_str(signature).is_equal(
		"2a5a5e549673b4ff773edfdab583c1d51a38e465fc7ec951e12782240d7346af"
	)


## 前提: なし。操作: create_headers を 2 回。
## 期待: 3 種のヘッダーが付き、nonce は毎回違う（サーバーは nonce の再利用を拒む）。
## timestamp は現在時刻に近い UNIX 秒、署名は 64 桁の 16 進。
func test_create_headers_has_three_headers_and_fresh_nonce() -> void:
	var first := ClientSignature.create_headers("{}")
	var second := ClientSignature.create_headers("{}")
	assert_int(first.size()).is_equal(3)
	var nonce_1 := FakeApiClient.header_value(first, "X-Client-Nonce")
	var nonce_2 := FakeApiClient.header_value(second, "X-Client-Nonce")
	assert_str(nonce_1).has_length(32)
	assert_str(nonce_1).is_not_equal(nonce_2)
	var timestamp := int(FakeApiClient.header_value(first, "X-Client-Timestamp"))
	assert_int(abs(timestamp - int(Time.get_unix_time_from_system()))).is_less(5)
	assert_str(FakeApiClient.header_value(first, "X-Client-Signature")).has_length(64)
