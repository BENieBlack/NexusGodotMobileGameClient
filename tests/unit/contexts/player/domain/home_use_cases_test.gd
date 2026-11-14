## GetHomeSummaryUseCase と GetStaminaDisplayUseCase の単体テスト（client_design.md 1-3・3・4）。
extends GdUnitTestSuite

const T0 := 1_800_000_000


func _login(
	repository: LocalPlayerRepository,
	sys_player: Dictionary,
	lists: Dictionary,
	diamond: Dictionary = {},
	offset: int = 0
) -> void:
	repository.replace(PlayerState.new(sys_player, lists, diamond, offset, offset != 0))


func _stamina_row(
	current: Variant = 42, at: Variant = "2027-01-15 08:00:00", rate: Variant = "1.00"
) -> Dictionary:
	return {
		"type": "normal",
		"current_stamina": current,
		"last_recovery_at": at,
		"recovery_rate_multiplier": rate,
	}


func _build(
	repository: LocalPlayerRepository, with_level := true, with_config := true
) -> GetHomeSummaryUseCase:
	var levels := FakeMstRepositories.Level.new()
	if with_level:
		levels.rows[1] = 50
	var config := FakeMstRepositories.Config.new()
	if with_config:
		config.put_int("stamina_recovery_interval_seconds", "300")
	return GetHomeSummaryUseCase.new(repository, levels, config)


## 前提: 全項目が揃った login。期待: 名前・ID・レベル・コイン・ダイヤの合計・スタミナの起点が入る。
func test_builds_full_summary() -> void:
	var repository := LocalPlayerRepository.new()
	_login(
		repository,
		{"my_id": "ABCD1234", "name": "taro", "level": 1.0},
		{
			"trx_stamina_list": [_stamina_row(42.0)],
			"trx_wallet_list": [{"mst_item_id": "coin", "free_amount": 1000}],
			"trx_item_list": [{"mst_item_id": "free_diamond", "free_amount": 50}],
		},
		{"paid_amount": 3}
	)
	var summary := _build(repository).handle()
	assert_bool(summary.is_logged_in).is_true()
	assert_str(summary.player_name).is_equal("taro")
	assert_str(summary.player_id).is_equal("ABCD1234")
	assert_int(summary.level).is_equal(1)
	assert_int(summary.coin).is_equal(1000)
	assert_int(summary.diamond_total).is_equal(53)
	var source := summary.stamina_source
	assert_bool(source.is_present).is_true()
	assert_int(source.current).is_equal(42)
	assert_int(source.max_stamina).is_equal(50)
	assert_int(source.interval_seconds).is_equal(300)
	assert_int(source.rate_x100).is_equal(100)
	assert_int(source.recovered_at_unix).is_equal(
		ServerDatetime.parse_to_unix("2027-01-15 08:00:00")
	)


## 前提: 未ログイン。期待: is_logged_in が偽。
func test_not_logged_in() -> void:
	assert_bool(_build(LocalPlayerRepository.new()).handle().is_logged_in).is_false()


## 前提: name が null。期待: "<null>" ではなく空文字。
func test_null_name_is_empty() -> void:
	var repository := LocalPlayerRepository.new()
	_login(repository, {"my_id": "a", "name": null, "level": 1}, {})
	assert_str(_build(repository).handle().player_name).is_equal("")


## 前提: 行なし（Coin 行なし・スタミナ行なし・level なし）。期待: コイン 0・is_present 偽・level -1。
func test_missing_rows() -> void:
	var repository := LocalPlayerRepository.new()
	_login(repository, {"my_id": "a"}, {})
	var summary := _build(repository).handle()
	assert_int(summary.coin).is_equal(0)
	assert_int(summary.level).is_equal(-1)
	assert_bool(summary.stamina_source.is_present).is_false()
	assert_int(summary.stamina_source.max_stamina).is_equal(-1)


## 前提: raid の行と削除された normal の行だけ。期待: 行なし扱い。normal が後ろにあれば拾う。
func test_only_normal_undeleted_row_is_used() -> void:
	var repository := LocalPlayerRepository.new()
	var raid := _stamina_row(5)
	raid["type"] = "raid"
	var deleted := _stamina_row(7)
	deleted["is_delete"] = true
	_login(repository, {"my_id": "a", "level": 1}, {"trx_stamina_list": [raid, deleted]})
	assert_bool(_build(repository).handle().stamina_source.is_present).is_false()
	_login(
		repository,
		{"my_id": "a", "level": 1},
		{"trx_stamina_list": [raid, deleted, _stamina_row(9)]}
	)
	assert_int(_build(repository).handle().stamina_source.current).is_equal(9)


## 前提: マスターが読めない（mst_player_level なし・mst_config なし）。期待: 最大値 -1・間隔 0（例外にしない）。
func test_master_unavailable() -> void:
	var repository := LocalPlayerRepository.new()
	_login(repository, {"my_id": "a", "level": 1}, {"trx_stamina_list": [_stamina_row()]})
	var source := _build(repository, false, false).handle().stamina_source
	assert_int(source.max_stamina).is_equal(-1)
	assert_int(source.interval_seconds).is_equal(0)
	assert_int(source.current).is_equal(42)


## 前提: 最大レベル超のレベル（行なし）・回復間隔が 0 / 負 / 整数でない。期待: 最大値 -1・間隔 0。
func test_invalid_master_values() -> void:
	var repository := LocalPlayerRepository.new()
	_login(repository, {"my_id": "a", "level": 101}, {"trx_stamina_list": [_stamina_row()]})
	assert_int(_build(repository).handle().stamina_source.max_stamina).is_equal(-1)
	_login(repository, {"my_id": "a", "level": 1}, {"trx_stamina_list": [_stamina_row()]})
	for bad in ["0", "-5", "abc", "1.5"]:
		var levels := FakeMstRepositories.Level.new()
		levels.rows[1] = 50
		var config := FakeMstRepositories.Config.new()
		config.put_int("stamina_recovery_interval_seconds", bad)
		var source := GetHomeSummaryUseCase.new(repository, levels, config).handle().stamina_source
		assert_int(source.interval_seconds).is_equal(0)


## 前提: 起点が読めない（時刻の書式不正・倍率が数値でない / 0）。期待: -1 / 0 の番兵。倍率 1.50 は 150、数値でも読む。
func test_unreadable_source_values() -> void:
	var repository := LocalPlayerRepository.new()
	_login(
		repository, {"my_id": "a", "level": 1}, {"trx_stamina_list": [_stamina_row(1, "bad", "x")]}
	)
	var source := _build(repository).handle().stamina_source
	assert_int(source.recovered_at_unix).is_equal(-1)
	assert_int(source.rate_x100).is_equal(0)
	_login(
		repository,
		{"my_id": "a", "level": 1},
		{"trx_stamina_list": [_stamina_row(1, null, "0.00")]}
	)
	assert_int(_build(repository).handle().stamina_source.rate_x100).is_equal(0)
	_login(
		repository,
		{"my_id": "a", "level": 1},
		{"trx_stamina_list": [_stamina_row(1, "2027-01-15 08:00:00", "1.50")]}
	)
	assert_int(_build(repository).handle().stamina_source.rate_x100).is_equal(150)
	_login(
		repository,
		{"my_id": "a", "level": 1},
		{"trx_stamina_list": [_stamina_row(1, "2027-01-15 08:00:00", 2)]}
	)
	assert_int(_build(repository).handle().stamina_source.rate_x100).is_equal(200)


## GetStaminaDisplayUseCase: now = 端末時計 + オフセット。端末が 1 時間進んでいても（オフセット -3600）補正される。
func test_stamina_display_uses_server_offset() -> void:
	var repository := LocalPlayerRepository.new()
	_login(repository, {"my_id": "a"}, {}, {}, -3600)
	var clock := FakeMstRepositories.FixedClock.new()
	clock.now = T0 + 3600 + 600  # 端末は 3600 秒進み、サーバー時刻では起点から 600 秒
	var source := StaminaSource.new(40, T0, 100, 50, 300, true)
	var display := GetStaminaDisplayUseCase.new(repository, clock).handle(source)
	assert_int(display.current).is_equal(42)
	# 補正なし（オフセット 0）だと 3 時間以内に最大値へ達してしまう
	_login(repository, {"my_id": "a"}, {})
	assert_int(GetStaminaDisplayUseCase.new(repository, clock).handle(source).current).is_equal(50)
