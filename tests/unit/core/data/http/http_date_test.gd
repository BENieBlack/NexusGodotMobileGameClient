## HttpDate（Date ヘッダーの解釈）と ApiClient.find_header の単体テスト。
extends GdUnitTestSuite


## 前提: RFC 7231 の形式。期待: UTC の UNIX 秒（Date は秒精度）。
func test_parses_imf_fixdate() -> void:
	assert_int(HttpDate.parse_to_unix("Sat, 14 Nov 2026 02:03:19 GMT")).is_equal(1794621799)
	assert_int(HttpDate.parse_to_unix("Thu, 01 Jan 1970 00:00:00 GMT")).is_equal(0)
	# 月名は大文字小文字を区別しない・前後の空白は除く
	assert_int(HttpDate.parse_to_unix("  Sat, 14 NOV 2026 02:03:19 GMT ")).is_equal(1794621799)


## 前提: 形式違い・月名不明・範囲外・空。期待: -1。
func test_invalid_is_failure() -> void:
	for text in [
		"",
		"garbage",
		"Sat, 14 Nov 2026 02:03:19",
		"Sat, 14 Foo 2026 02:03:19 GMT",
		"Sat, 32 Nov 2026 02:03:19 GMT",
		"Sat, 14 Nov 2026 25:03:19 GMT",
		"2026-11-14 02:03:19",
	]:
		assert_int(HttpDate.parse_to_unix(text)).is_equal(HttpDate.INVALID)


## 前提: 大文字小文字違い・値に ":" を含むヘッダー。期待: 名前は大文字小文字を区別せず、値は最初の ":" の後ろ全部。
func test_find_header() -> void:
	var headers := PackedStringArray(
		["Content-Type: application/json", "date: Sat, 14 Nov 2026 02:03:19 GMT"]
	)
	assert_str(ApiClient.find_header(headers, "Date")).is_equal("Sat, 14 Nov 2026 02:03:19 GMT")
	assert_str(ApiClient.find_header(headers, "X-None")).is_empty()
	assert_str(ApiClient.find_header(PackedStringArray(["broken"]), "broken")).is_empty()
