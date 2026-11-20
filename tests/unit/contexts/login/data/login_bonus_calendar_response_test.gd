## LoginBonusCalendarResponse・LoginBonusCalendarsResponse・ReceiveVipLoginBonusResponse の単体テスト
## （client_design.md 4 節・9 節）。サーバー api.md の例の JSON のうち進捗の項目を固定の入力にして、
## last_received_day の名前の取り違えと、null・欠落・型違いの扱い（D3）を確かめる。
extends GdUnitTestSuite


func _normal() -> Dictionary:
	return {
		"mst_login_bonus_id": "lb1",
		"last_received_day": 3,
		"is_granted_today": true,
		"is_granted_now": true,
	}


func _vip() -> Dictionary:
	return {
		"mst_vip_login_bonus_id": "vip5",
		"last_received_day": 2.0,
		"is_granted_today": true,
		"is_granted_now": false,
		"vip_level": 5,
		"can_re_receive": true,
	}


## 前提: 正常な通常の段・VIP の段（全日の報酬は応答に無い）。期待: 短い名前（mst_id・last_day）に対応して読める。
func test_normal_and_vip_stage_are_parsed_without_rewards() -> void:
	var normal := LoginBonusCalendarResponse.from_variant(_normal(), false)
	assert_str(normal.mst_id).is_equal("lb1")
	assert_int(normal.last_day).is_equal(3)
	assert_bool(normal.is_granted_today).is_true()
	assert_bool(normal.is_granted_now).is_true()
	assert_bool(normal.can_re_receive).is_false()
	assert_int(normal.vip_level).is_equal(0)

	var vip := LoginBonusCalendarResponse.from_variant(_vip(), true)
	assert_str(vip.mst_id).is_equal("vip5")
	assert_int(vip.last_day).is_equal(2)
	assert_bool(vip.can_re_receive).is_true()
	assert_int(vip.vip_level).is_equal(5)


## 前提: null・キー無し（Variant の null）・Dictionary でない値。期待: その段なし（null）。
func test_null_and_non_dictionary_mean_no_stage() -> void:
	assert_object(LoginBonusCalendarResponse.from_variant(null, false)).is_null()
	assert_object(LoginBonusCalendarResponse.from_variant("text", false)).is_null()
	assert_object(LoginBonusCalendarResponse.from_variant([1], true)).is_null()


## 前提: last_received_day が null・欠落・数値でない。期待: 0。
func test_last_day_null_or_missing_is_zero() -> void:
	var data := _normal()
	data["last_received_day"] = null
	assert_int(LoginBonusCalendarResponse.from_variant(data, false).last_day).is_equal(0)
	data.erase("last_received_day")
	assert_int(LoginBonusCalendarResponse.from_variant(data, false).last_day).is_equal(0)
	data["last_received_day"] = "3"
	assert_int(LoginBonusCalendarResponse.from_variant(data, false).last_day).is_equal(0)


## 前提: 真偽値が null・0/1・文字列。期待: 真偽値型のときだけ真になり、それ以外は偽（安全側）。
func test_non_bool_flags_fall_to_false() -> void:
	for bad: Variant in [null, 1, 0, "true", "1"]:
		var data := _vip()
		data["is_granted_today"] = bad
		data["is_granted_now"] = bad
		data["can_re_receive"] = bad
		var calendar := LoginBonusCalendarResponse.from_variant(data, true)
		assert_bool(calendar.is_granted_today).is_false()
		assert_bool(calendar.is_granted_now).is_false()
		assert_bool(calendar.can_re_receive).is_false()


## 前提: VIP の ID が欠落・null で can_re_receive が真。期待: 送る ID が無いので can_re_receive は偽。ID は空文字。
func test_vip_without_id_cannot_re_receive() -> void:
	var data := _vip()
	data["mst_vip_login_bonus_id"] = null
	var calendar := LoginBonusCalendarResponse.from_variant(data, true)
	assert_str(calendar.mst_id).is_empty()
	assert_bool(calendar.can_re_receive).is_false()


## 前提: 通常の段に can_re_receive・vip_level が付いている。期待: 無視する（VIP のみ読む）。
func test_normal_stage_ignores_vip_only_fields() -> void:
	var data := _normal()
	data["can_re_receive"] = true
	data["vip_level"] = 9
	var calendar := LoginBonusCalendarResponse.from_variant(data, false)
	assert_bool(calendar.can_re_receive).is_false()
	assert_int(calendar.vip_level).is_equal(0)


## 前提: 2 キーの束・片方 null・キー無し。期待: それぞれの段が読めるか null になる。旧応答は両方 null。
func test_calendars_response_handles_missing_and_null_keys() -> void:
	var both := LoginBonusCalendarsResponse.from_dict(
		{"login_bonus_calendar": _normal(), "vip_login_bonus_calendar": _vip()}
	)
	assert_str(both.normal.mst_id).is_equal("lb1")
	assert_str(both.vip.mst_id).is_equal("vip5")

	var only_vip := LoginBonusCalendarsResponse.from_dict(
		{"login_bonus_calendar": null, "vip_login_bonus_calendar": _vip()}
	)
	assert_object(only_vip.normal).is_null()
	assert_object(only_vip.vip).is_not_null()

	var old := LoginBonusCalendarsResponse.from_dict({"sys_player": {}})
	assert_object(old.normal).is_null()
	assert_object(old.vip).is_null()
	assert_bool(old.has_any()).is_false()


## 前提: 再受け取りの応答（4 キー）。期待: 報酬・VIP の段（is_granted_now 真・can_re_receive 偽）・
## updated_resources が取り出せる。trx_vip_login_bonus は読まない。
func test_receive_response_extracts_all_keys() -> void:
	var vip := _vip()
	vip["is_granted_now"] = true
	vip["can_re_receive"] = false
	var result := (
		ReceiveVipLoginBonusResponse
		. from_dict(
			{
				"trx_vip_login_bonus": {"mst_vip_login_bonus_id": "vip5", "day": 2},
				"login_bonus_list":
				[{"unique_id": "u", "type": "item", "id": "free_diamond", "amount": 300.0}],
				"vip_login_bonus_calendar": vip,
				"updated_resources": {"trx_item_list": [{"mst_item_id": "free_diamond"}]},
			}
		)
		. to_domain()
	)
	assert_bool(result.ok).is_true()
	assert_int(result.rewards.size()).is_equal(1)
	assert_int(result.rewards[0].amount).is_equal(300)
	assert_bool(result.vip_calendar.is_granted_now).is_true()
	assert_bool(result.vip_calendar.can_re_receive).is_false()
	assert_int(result.updated_resources["trx_item_list"].size()).is_equal(1)


## 前提: 4 キーすべて欠落・null・型違い。期待: 失敗にせず、空の報酬・null の段・空の updated_resources。
func test_receive_response_tolerates_missing_keys() -> void:
	for body: Dictionary in [
		{},
		{
			"login_bonus_list": null,
			"vip_login_bonus_calendar": null,
			"updated_resources": null,
			"trx_vip_login_bonus": null
		},
		{"login_bonus_list": "x", "vip_login_bonus_calendar": 5, "updated_resources": []},
	]:
		var result := ReceiveVipLoginBonusResponse.from_dict(body).to_domain()
		assert_bool(result.ok).is_true()
		assert_array(result.rewards).is_empty()
		assert_object(result.vip_calendar).is_null()
		assert_dict(result.updated_resources).is_empty()
