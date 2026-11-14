## ServerDatetime（`Y-m-d H:i:s` の UTC を UNIX 秒に読む純粋関数）の単体テスト。
extends GdUnitTestSuite


## 前提: 正しい書式。期待: UTC の UNIX 秒（設計 0-e の実測値 1794621799）。
func test_parses_valid_datetime_as_utc() -> void:
	assert_int(ServerDatetime.parse_to_unix("2026-11-14 02:03:19")).is_equal(1794621799)
	assert_int(ServerDatetime.parse_to_unix("1970-01-01 00:00:00")).is_equal(0)


## 前提: 書式違い・範囲外・存在しない日・空。期待: 0 ではなく -1（失敗）。
func test_invalid_text_is_failure_not_zero() -> void:
	for text in [
		"",
		"2026-11-14",
		"2026-11-14T02:03:19",
		"2026-11-14 02:03",
		"2026/11/14 02:03:19",
		"2026-11-14 02:03:19Z",
		" 2026-11-14 02:03:19",
		"abcd-ef-gh ij:kl:mn",
		"2026-13-01 00:00:00",
		"2026-00-10 00:00:00",
		"2026-11-32 00:00:00",
		"2026-11-14 24:00:00",
		"2026-11-14 00:60:00",
		"2026-11-14 00:00:60",
		"2026-02-30 00:00:00",
		"1969-12-31 23:59:59",
	]:
		assert_int(ServerDatetime.parse_to_unix(text)).is_equal(ServerDatetime.INVALID)


## 前提: うるう日。期待: 2024-02-29 は読め、2026-02-29 は失敗。
func test_leap_day() -> void:
	assert_int(ServerDatetime.parse_to_unix("2024-02-29 00:00:00")).is_greater(0)
	assert_int(ServerDatetime.parse_to_unix("2026-02-29 00:00:00")).is_equal(-1)
