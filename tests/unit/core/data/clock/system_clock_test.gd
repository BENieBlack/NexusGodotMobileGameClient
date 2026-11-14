## SystemClock の単体テスト（端末時刻とデバッグ用のずれ）。
extends GdUnitTestSuite


## 前提: ずれ 0。期待: 端末の UNIX 秒に近い値（数秒以内）。
func test_now_matches_system_time() -> void:
	var clock := SystemClock.new()
	assert_int(absi(clock.now_unix() - int(Time.get_unix_time_from_system()))).is_less_equal(1)


## 前提: skew_seconds を ±3600。期待: その分だけ進む・遅れる（e2e の端末時計のずれ）。
func test_skew_shifts_now() -> void:
	var clock := SystemClock.new()
	clock.skew_seconds = 3600
	assert_int(clock.now_unix() - int(Time.get_unix_time_from_system())).is_between(3599, 3601)
	clock.skew_seconds = -3600
	assert_int(clock.now_unix() - int(Time.get_unix_time_from_system())).is_between(-3601, -3599)
