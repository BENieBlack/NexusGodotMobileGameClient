## LoginBonusStageMasterReader の単体テスト（マスターの報酬行 → 段のマスター。client_design.md 4 節）。
## 偽の Repository（FakeLoginRepositories）で、日の絞り込み・補完・数量・並び・種別の扱いを確かめる。
extends GdUnitTestSuite

var _normal: FakeLoginRepositories.FakeMstNormal
var _vip: FakeLoginRepositories.FakeMstVip
var _reader: LoginBonusStageMasterReader


func before_test() -> void:
	_normal = FakeLoginRepositories.FakeMstNormal.new()
	_vip = FakeLoginRepositories.FakeMstVip.new()
	_reader = LoginBonusStageMasterReader.new(_normal, _vip)


func _calendars(normal_id: String = "lb1", vip_id: String = "") -> LoginBonusCalendars:
	return LoginBonusCalendars.new(
		LoginBonusCalendar.new(normal_id) if normal_id != "" else null,
		LoginBonusCalendar.new(vip_id) if vip_id != "" else null
	)


## 前提: 7 日の周期で、day = 0（カムバック）・範囲外（8）・content_type 空の行を含む。
## 期待: 1〜7 の日が作られ（行の無い日は空の日）、day 0・範囲外・種別空の行は捨てられる。
func test_filters_days_fills_empty_days_and_drops_bad_rows() -> void:
	_normal.lookups["lb1"] = (
		FakeLoginRepositories
		. normal_lookup(
			"lb1",
			7,
			[
				{"day": 0, "type": "item", "id": "comeback"},
				{"day": 1, "type": "item", "id": "a"},
				{"day": 3, "type": "wallet", "id": "gold"},
				{"day": 8, "type": "item", "id": "over"},
				{"day": 2, "type": "", "id": "empty_type"},
			]
		)
	)
	var masters := _reader.read(_calendars())
	var stage := masters.normal
	assert_int(stage.cycle_days).is_equal(7)
	assert_int(stage.days.size()).is_equal(7)
	assert_int(stage.day_of(1).rewards.size()).is_equal(1)
	assert_array(stage.day_of(2).rewards).is_empty()
	assert_str(stage.day_of(3).rewards[0].type).is_equal("wallet")
	assert_array(stage.day_of(7).rewards).is_empty()
	assert_object(stage.day_of(0)).is_null()
	assert_object(stage.day_of(8)).is_null()


## 前提: 数量 content_quantity = 100・amount = 3、is_paid 真の行・偽の行。
## 期待: 数量は 300、is_paid が真の行だけ metadata に is_paid: true（VIP の行は is_paid 無し）。
func test_quantity_is_multiplied_and_is_paid_goes_to_metadata() -> void:
	_normal.lookups["lb1"] = (
		FakeLoginRepositories
		. normal_lookup(
			"lb1",
			2,
			[
				{
					"day": 1,
					"type": "wallet",
					"id": "gold",
					"qty": 100,
					"amount": 3,
					"is_paid": true
				},
				{"day": 2, "type": "item", "id": "a", "qty": 5, "amount": 1},
			]
		)
	)
	_vip.lookups["vip5"] = FakeLoginRepositories.vip_lookup(
		"vip5", 1, [{"day": 1, "type": "item", "id": "free_diamond", "qty": 50, "amount": 4}]
	)
	var masters := _reader.read(_calendars("lb1", "vip5"))
	var paid := masters.normal.day_of(1).rewards[0]
	assert_int(paid.amount).is_equal(300)
	assert_bool(paid.metadata.get("is_paid", false)).is_true()
	assert_bool(masters.normal.day_of(2).rewards[0].metadata.has("is_paid")).is_false()
	assert_int(masters.vip.day_of(1).rewards[0].amount).is_equal(200)
	assert_bool(masters.vip.day_of(1).rewards[0].metadata.has("is_paid")).is_false()


## 前提: 未知の content_type（foo）。期待: 捨てずに残す（画面が unknown の絵で出す）。
## 並びは Repository の並びのまま（ここで並べ替えない）。
func test_unknown_content_type_is_kept_and_order_is_preserved() -> void:
	_normal.lookups["lb1"] = (
		FakeLoginRepositories
		. normal_lookup(
			"lb1",
			1,
			[
				{"day": 1, "type": "foo", "id": "x", "sort_desc": 9},
				{"day": 1, "type": "item", "id": "a", "sort_desc": 1},
			]
		)
	)
	var rewards := _reader.read(_calendars()).normal.day_of(1).rewards
	assert_int(rewards.size()).is_equal(2)
	assert_str(rewards[0].type).is_equal("foo")
	assert_str(rewards[1].id).is_equal("a")


## 前提: 周期の日数が 0・9（表示できない）。期待: 周期はそのまま持ち、days は作らない（is_displayable が偽）。
func test_non_displayable_cycle_has_no_days() -> void:
	_normal.lookups["lb1"] = FakeLoginRepositories.normal_lookup("lb1", 9)
	var stage := _reader.read(_calendars()).normal
	assert_int(stage.cycle_days).is_equal(9)
	assert_array(stage.days).is_empty()
	assert_bool(stage.is_displayable()).is_false()
	_normal.lookups["lb1"] = FakeLoginRepositories.normal_lookup("lb1", 0)
	assert_bool(_reader.read(_calendars()).normal.is_displayable()).is_false()


## 前提: 進捗の無い段・mst_id が空の段・引けない ID。期待: 進捗の無い段は引かない。
## 引けない段は null で、種別が残る（NOT_FOUND）。mst_id が空のときも引かない。
func test_lookup_only_for_present_stages_and_keeps_status() -> void:
	_normal.lookups["lb1"] = MstLoginBonusLookup.new(MstLookupStatus.Status.NOT_FOUND)
	var masters := _reader.read(_calendars("lb1", ""))
	assert_array(_vip.asked).is_empty()
	assert_object(masters.normal).is_null()
	assert_int(masters.normal_status).is_equal(MstLookupStatus.Status.NOT_FOUND)
	assert_bool(masters.has_vip_lookup).is_false()

	var empty_id := _reader.read(LoginBonusCalendars.new(LoginBonusCalendar.new("")))
	assert_array(_normal.asked).contains_exactly(["lb1"])
	assert_object(empty_id.normal).is_null()
	assert_bool(empty_id.covers(LoginBonusCalendars.new(LoginBonusCalendar.new("")))).is_false()
