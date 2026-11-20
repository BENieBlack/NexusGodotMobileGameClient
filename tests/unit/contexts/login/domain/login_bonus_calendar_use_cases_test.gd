## Fetch・ReceiveVip の UseCase の単体テスト（偽の Repository。client_design.md 3 節）。
extends GdUnitTestSuite

var _api: FakeLoginRepositories.FakeCalendar
var _bonuses: LocalLoginBonusRepository
var _player: LocalPlayerRepository
var _fetch: FetchLoginBonusCalendarsUseCase
var _receive: ReceiveVipLoginBonusUseCase


func before_test() -> void:
	_api = FakeLoginRepositories.FakeCalendar.new()
	_bonuses = LocalLoginBonusRepository.new()
	_player = LocalPlayerRepository.new()
	_fetch = FetchLoginBonusCalendarsUseCase.new(_api, _bonuses)
	_receive = ReceiveVipLoginBonusUseCase.new(
		_api, _bonuses, ApplyUpdatedResourcesUseCase.new(_player)
	)


func _error(kind: AppError.Kind) -> AppError:
	return AppError.new(kind)


## 前提: list が成功。期待: メモリの保持が置き換わる（応答に無い段は null になる）。冪等キーは渡さない（契約に無い）。
func test_fetch_success_replaces_memory() -> void:
	_bonuses.replace_calendars(
		LoginBonusCalendars.new(LoginBonusCalendar.new("old"), LoginBonusCalendar.new("oldvip"))
	)
	_api.fetch_result = FetchLoginBonusCalendarsResult.new(
		null, LoginBonusCalendars.new(LoginBonusCalendar.new("lb1", 2, true))
	)
	var result := await _fetch.handle()
	assert_bool(result.ok).is_true()
	assert_str(_bonuses.calendars().normal.mst_id).is_equal("lb1")
	assert_object(_bonuses.calendars().vip).is_null()


## 前提: list が失敗。期待: error を返し、メモリは変えない。
func test_fetch_failure_keeps_memory() -> void:
	_bonuses.replace_calendars(LoginBonusCalendars.new(LoginBonusCalendar.new("old")))
	_api.fetch_result = FetchLoginBonusCalendarsResult.new(_error(AppError.Kind.NETWORK))
	var result := await _fetch.handle()
	assert_bool(result.ok).is_false()
	assert_str(_bonuses.calendars().normal.mst_id).is_equal("old")


## 前提: 再受け取りが成功（VIP の段・報酬・updated_resources つき）。期待:
##   VIP の段だけ応答の値（is_granted_now 真・can_re_receive 偽）に置き換わり、通常の段は変わらない。
##   updated_resources が所持数に取り込まれる。送った ID と冪等キーが渡る。報酬が結果に載る。
func test_receive_success_updates_vip_only_and_applies_resources() -> void:
	_player.replace(
		PlayerState.new(
			{"my_id": "a"}, {"trx_item_list": [{"mst_item_id": "free_diamond", "free_amount": 1}]}
		)
	)
	_bonuses.replace_calendars(
		LoginBonusCalendars.new(
			LoginBonusCalendar.new("lb1", 2, true, false),
			LoginBonusCalendar.new("vip5", 2, true, false, true, 5)
		)
	)
	var rewards: Array[LoginBonus] = [LoginBonus.new("u", "item", "free_diamond", 300)]
	_api.receive_result = ReceiveVipLoginBonusResult.new(
		null,
		rewards,
		LoginBonusCalendar.new("vip5", 2, true, true, false, 5),
		{"trx_item_list": [{"mst_item_id": "free_diamond", "free_amount": 301}]}
	)
	var result := await _receive.handle("vip5", "key-1")

	assert_bool(result.ok).is_true()
	assert_array(_api.receive_calls).contains_exactly([{"id": "vip5", "key": "key-1"}])
	assert_int(result.rewards.size()).is_equal(1)
	var vip := _bonuses.calendars().vip
	assert_bool(vip.is_granted_now).is_true()
	assert_bool(vip.can_re_receive).is_false()
	var normal := _bonuses.calendars().normal
	assert_bool(normal.is_granted_now).is_false()
	assert_int(normal.last_day).is_equal(2)
	assert_int(int(_player.current().trx_list("trx_item_list")[0]["free_amount"])).is_equal(301)


## 前提: 応答の VIP の段が読めない（null）。期待: メモリの VIP の段を再受け取り済みに複製して代える。
## 報酬は空のまま（成功は成功）。メモリに VIP の段も無ければ何も置かない。
func test_receive_falls_back_to_duplicate_when_response_calendar_is_unreadable() -> void:
	_bonuses.replace_calendars(
		LoginBonusCalendars.new(null, LoginBonusCalendar.new("vip5", 3, true, false, true, 5))
	)
	_api.receive_result = ReceiveVipLoginBonusResult.new()
	var result := await _receive.handle("vip5", "k")
	assert_bool(result.ok).is_true()
	assert_bool(_bonuses.calendars().vip.is_granted_now).is_true()
	assert_bool(_bonuses.calendars().vip.can_re_receive).is_false()
	assert_int(_bonuses.calendars().vip.last_day).is_equal(3)
	assert_array(result.rewards).is_empty()

	_bonuses.clear()
	_api.receive_result = ReceiveVipLoginBonusResult.new()
	await _receive.handle("vip5", "k2")
	assert_object(_bonuses.calendars().vip).is_null()


## 前提: 失敗（BUSINESS 26001・NETWORK）。期待: 何も反映しない（所持数・段）。BUSINESS は冪等キーを再利用できない。
func test_receive_failure_applies_nothing() -> void:
	_player.replace(
		PlayerState.new({"my_id": "a"}, {"trx_item_list": [{"mst_item_id": "x", "free_amount": 1}]})
	)
	_bonuses.replace_calendars(
		LoginBonusCalendars.new(null, LoginBonusCalendar.new("vip5", 1, true, false, true))
	)
	var business := _error(AppError.Kind.BUSINESS)
	business.error_code = 26001
	_api.receive_result = ReceiveVipLoginBonusResult.new(
		business, [], null, {"trx_item_list": [{"mst_item_id": "x", "free_amount": 999}]}
	)
	var result := await _receive.handle("vip5", "k")

	assert_bool(result.ok).is_false()
	assert_int(result.error.error_code).is_equal(26001)
	assert_bool(IdempotencyKey.can_reuse(result.error.kind)).is_false()
	assert_bool(_bonuses.calendars().vip.can_re_receive).is_true()
	assert_int(int(_player.current().trx_list("trx_item_list")[0]["free_amount"])).is_equal(1)

	_api.receive_result = ReceiveVipLoginBonusResult.new(_error(AppError.Kind.NETWORK))
	var network := await _receive.handle("vip5", "k")
	assert_bool(IdempotencyKey.can_reuse(network.error.kind)).is_true()
