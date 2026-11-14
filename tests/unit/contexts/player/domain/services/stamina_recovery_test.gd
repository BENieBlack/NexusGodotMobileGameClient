## StaminaRecovery の単体テスト（client_design.md 3-1・1-3 の状態表）。
## now を引数で渡すので時計に依存しない。サーバーの式 floor(経過秒 × 倍率 ÷ 間隔) との一致も確かめる。
extends GdUnitTestSuite

const T0 := 1_800_000_000


## 起点を作る。rate は 100 倍の整数（100 = 1.0 倍）。
func _source(
	current: int,
	max_stamina: int = 50,
	interval: int = 300,
	rate: int = 100,
	recovered_at: int = T0
) -> StaminaSource:
	return StaminaSource.new(current, recovered_at, rate, max_stamina, interval, true)


## 前提: 間隔 300 秒・倍率 1.0。経過 299 / 300 / 601 秒。期待: 0 / 1 / 2 点。残りは次の 1 点まで。
func test_points_follow_elapsed() -> void:
	var source := _source(40)
	var d0 := StaminaRecovery.calculate(source, T0 + 299)
	assert_int(d0.current).is_equal(40)
	assert_int(d0.seconds_to_next).is_equal(1)
	var d1 := StaminaRecovery.calculate(source, T0 + 300)
	assert_int(d1.current).is_equal(41)
	assert_int(d1.seconds_to_next).is_equal(300)
	var d2 := StaminaRecovery.calculate(source, T0 + 601)
	assert_int(d2.current).is_equal(42)
	assert_int(d2.seconds_to_next).is_equal(299)


## 前提: 倍率 1 / 1.5 / 2。期待: サーバーの式 floor(経過 × 倍率 ÷ 間隔) と、全ての経過秒で一致する。
func test_matches_server_formula_for_rates() -> void:
	for rate_x100 in [100, 150, 200]:
		var rate: float = rate_x100 / 100.0
		var source := _source(0, 1000, 300, rate_x100)
		for elapsed in range(0, 2000, 7):
			var expected := int(floor(elapsed * rate / 300.0))
			var actual := StaminaRecovery.calculate(source, T0 + elapsed).current
			assert_int(actual).is_equal(expected)


## 前提: 間隔 300・倍率 1.5（1 点 200 秒）。期待: 残り時間は割り切れなくても切り上げで、点が増える瞬間に 0 にならない。
func test_remaining_time_with_rate_1_5() -> void:
	var source := _source(10, 50, 300, 150)
	assert_int(StaminaRecovery.calculate(source, T0).seconds_to_next).is_equal(200)
	assert_int(StaminaRecovery.calculate(source, T0 + 199).seconds_to_next).is_equal(1)
	var d := StaminaRecovery.calculate(source, T0 + 200)
	assert_int(d.current).is_equal(11)
	assert_int(d.seconds_to_next).is_equal(200)
	# 倍率 1.5・間隔 100: 1 点 66.67 秒 → 2 点目は 133.33 秒で切り上げ 134
	var odd := _source(10, 50, 100, 150)
	assert_int(StaminaRecovery.calculate(odd, T0 + 67).seconds_to_next).is_equal(67)


## 前提: 最大値の手前で長時間経過。期待: 最大値で止まり、残り時間なし。
func test_stops_at_max() -> void:
	var d := StaminaRecovery.calculate(_source(48), T0 + 100000)
	assert_int(d.current).is_equal(50)
	assert_int(d.seconds_to_next).is_equal(-1)


## 前提: 現在値 = 最大値で、last_recovery_at が遠い過去（サーバーは最大値のとき進めない）。
## 期待: 回復を足さず、残り時間なし（最大値判定が経過時間の計算より先）。
func test_at_max_does_not_recover_even_with_large_elapsed() -> void:
	var d := StaminaRecovery.calculate(_source(50), T0 + 100000)
	assert_int(d.current).is_equal(50)
	assert_int(d.seconds_to_next).is_equal(-1)


## 前提: 現在値 55 > 最大 50（レベルアップ時の加算）。期待: 丸めず 55 / 50、残り時間なし、増えない。
func test_over_max_is_not_clamped() -> void:
	var d := StaminaRecovery.calculate(_source(55), T0 + 100000)
	assert_int(d.current).is_equal(55)
	assert_int(d.max_stamina).is_equal(50)
	assert_int(d.seconds_to_next).is_equal(-1)


## 前提: 端末時計が起点より過去（負の経過）。期待: 経過 0 として起点のまま、残りは 1 点分の全体。
func test_negative_elapsed_is_zero() -> void:
	var d := StaminaRecovery.calculate(_source(40), T0 - 500)
	assert_int(d.current).is_equal(40)
	assert_int(d.seconds_to_next).is_equal(300)


## 前提: 計算できない条件（最大値不明・倍率 0・間隔 0・起点が読めない）。
## 期待: 現在値は起点のまま・残り時間なし（最大値不明は max_stamina = -1 のまま）。
func test_cannot_compute_keeps_source_value() -> void:
	var cases := {
		"max unknown": _source(42, -1),
		"rate 0": _source(42, 50, 300, 0),
		"interval 0": _source(42, 50, 0),
		"unreadable time": _source(42, 50, 300, 100, ServerDatetime.INVALID),
	}
	for label in cases:
		var d := StaminaRecovery.calculate(cases[label], T0 + 100000)
		assert_int(d.current).is_equal(42)
		assert_int(d.seconds_to_next).is_equal(-1)
		assert_bool(d.is_present).is_true()
	assert_int(StaminaRecovery.calculate(cases["max unknown"], T0).max_stamina).is_equal(-1)


## 前提: スタミナ行なし。期待: is_present が偽（「-」表示）。
func test_not_present() -> void:
	var d := StaminaRecovery.calculate(StaminaSource.new(), T0)
	assert_bool(d.is_present).is_false()
	assert_int(d.seconds_to_next).is_equal(-1)


## 前提: 同じ起点を、時刻を進めたり戻したりして何度も計算する。
## 期待: 同じ now なら常に同じ値（結果を書き戻さないので二重加算にならない）。起点は変わらない。
func test_repeated_calculation_does_not_double_count() -> void:
	var source := _source(40)
	var first := StaminaRecovery.calculate(source, T0 + 650).current
	for i in range(5):
		StaminaRecovery.calculate(source, T0 + 100 * i)
	assert_int(StaminaRecovery.calculate(source, T0 + 650).current).is_equal(first)
	assert_int(first).is_equal(42)
	assert_int(source.current).is_equal(40)
