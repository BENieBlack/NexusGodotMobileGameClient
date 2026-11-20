## PrepareLoginBonusMasterUseCase の単体テスト（古いマスターの再取得は 1 回だけ。client_design.md 2-4）。
extends GdUnitTestSuite

var _normal: FakeLoginRepositories.FakeMstNormal
var _vip: FakeLoginRepositories.FakeMstVip
var _check: FakeLoginRepositories.FakeCheckMaster
var _use_case: PrepareLoginBonusMasterUseCase

var _calendars := LoginBonusCalendars.new(
	LoginBonusCalendar.new("lb1"), LoginBonusCalendar.new("vip5")
)


func before_test() -> void:
	_normal = FakeLoginRepositories.FakeMstNormal.new()
	_vip = FakeLoginRepositories.FakeMstVip.new()
	_check = FakeLoginRepositories.FakeCheckMaster.new()
	_use_case = PrepareLoginBonusMasterUseCase.new(
		LoginBonusStageMasterReader.new(_normal, _vip), _check
	)


func _put_normal() -> void:
	_normal.lookups["lb1"] = FakeLoginRepositories.normal_lookup("lb1", 7)


func _put_vip() -> void:
	_vip.lookups["vip5"] = FakeLoginRepositories.vip_lookup("vip5", 7)


## 前提: 2 段とも引ける。期待: 再取得しない（handle を呼ばない）・covers が真。
func test_all_found_does_not_refetch() -> void:
	_put_normal()
	_put_vip()
	var result := await _use_case.handle(_calendars)
	assert_bool(result.covers).is_true()
	assert_bool(result.refetched).is_false()
	assert_int(_check.call_count).is_equal(0)


## 前提: 引けない段があり、再取得（UPDATED）でマスターが入る。
## 期待: handle() を 1 回だけ呼び、引き直して引ける。
func test_missing_stage_refetches_once_and_reads_again() -> void:
	_put_normal()
	_check.on_handle = func(): _put_vip()
	var result := await _use_case.handle(_calendars)
	assert_int(_check.call_count).is_equal(1)
	assert_bool(result.refetched).is_true()
	assert_bool(result.covers).is_true()
	assert_object(result.masters.vip).is_not_null()


## 前提: 再取得（UPDATED）後も引けない。期待: handle は 1 回のまま・covers が偽（画面は文字へ。繰り返さない）。
func test_still_missing_after_refetch_is_not_covered_and_does_not_loop() -> void:
	_put_normal()
	var result := await _use_case.handle(_calendars)
	assert_int(_check.call_count).is_equal(1)
	assert_bool(result.covers).is_false()
	assert_object(result.masters.normal).is_not_null()
	assert_object(result.masters.vip).is_null()


## 前提: 再取得が FAILED・IN_PROGRESS・UP_TO_DATE。期待: 引き直さず、引けない段は出せない（covers が偽）。
func test_failed_in_progress_up_to_date_do_not_read_again() -> void:
	for status in [
		CheckMasterDataResult.Status.FAILED,
		CheckMasterDataResult.Status.IN_PROGRESS,
		CheckMasterDataResult.Status.UP_TO_DATE,
	]:
		_check.status = status
		_check.call_count = 0
		_normal.asked.clear()
		# 再取得でマスターが入っても、UPDATED でなければ引き直さない
		_check.on_handle = func(): _put_vip()
		_put_normal()
		_vip.lookups.clear()
		var result := await _use_case.handle(_calendars)
		assert_int(_check.call_count).is_equal(1)
		assert_int(_normal.asked.size()).is_equal(1)
		assert_bool(result.covers).is_false()
		assert_int(result.check_status).is_equal(status)


## 前提: 読めない（UNREADABLE。古い配信ファイルで列なし）・行なし（NOT_FOUND）。
## 期待: どちらも同じ再取得の対象（1 回）。種別は結果の masters に残る。
func test_unreadable_and_not_found_both_trigger_refetch() -> void:
	_put_vip()
	_normal.lookups["lb1"] = MstLoginBonusLookup.new(MstLookupStatus.Status.UNREADABLE)
	var unreadable := await _use_case.handle(_calendars)
	assert_int(_check.call_count).is_equal(1)
	assert_int(unreadable.masters.normal_status).is_equal(MstLookupStatus.Status.UNREADABLE)

	_normal.lookups["lb1"] = MstLoginBonusLookup.new(MstLookupStatus.Status.NOT_FOUND)
	var not_found := await _use_case.handle(_calendars)
	assert_int(_check.call_count).is_equal(2)
	assert_int(not_found.masters.normal_status).is_equal(MstLookupStatus.Status.NOT_FOUND)


## 前提: 進捗の段が無い（両方 null）。期待: 引くものが無いので再取得しない。covers は真。
func test_no_stage_means_nothing_to_look_up() -> void:
	var result := await _use_case.handle(LoginBonusCalendars.new())
	assert_int(_check.call_count).is_equal(0)
	assert_bool(result.covers).is_true()
