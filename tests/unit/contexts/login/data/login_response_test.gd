## LoginResponse（login 応答の取り込み）の単体テスト。null と欠落を同じに扱う規則（D3）と、
## 5 種の一覧・単数の trx_diamond・ログインボーナスの変換を確かめる。
extends GdUnitTestSuite


func _full_body() -> Dictionary:
	return {
		"sys_player": {"my_id": "abc", "level": 1, "total_paid_amount": "0.00"},
		"trx_unit_list": [{"trx_unit_id": "u1"}],
		"trx_item_list": [{"mst_item_id": "potion"}, {"mst_item_id": "ether"}],
		"trx_wallet_list": [{"mst_item_id": "gold"}],
		"trx_diamond": {"platform": "Apple", "paid_amount": 30},
		"trx_equipment_list": [{"trx_equipment_id": "e1"}],
		"trx_stamina_list": [{"type": "main", "recovery_rate_multiplier": "1.00"}],
		"login_bonus_list":
		[
			{
				"unique_id": "x",
				"type": "gold",
				"id": "gold",
				"amount": 5000.0,
				"expire_at": null,
				"metadata": null
			}
		],
	}


## 前提: 9 項目すべてがある応答。操作: from_dict → to_domain。
## 期待: sys_player と 5 種の件数、ログインボーナスの型（amount は int、null は空）が取り込める。
func test_full_response_is_imported() -> void:
	var result := LoginResponse.from_dict(_full_body()).to_domain()

	assert_bool(result.ok).is_true()
	assert_str(str(result.sys_player["my_id"])).is_equal("abc")
	(
		assert_array(result.trx_lists.keys())
		. contains_exactly_in_any_order(
			[
				"trx_unit_list",
				"trx_item_list",
				"trx_wallet_list",
				"trx_equipment_list",
				"trx_stamina_list",
			]
		)
	)
	assert_int(result.trx_lists["trx_unit_list"].size()).is_equal(1)
	assert_int(result.trx_lists["trx_item_list"].size()).is_equal(2)
	assert_int(result.trx_lists["trx_wallet_list"].size()).is_equal(1)
	assert_bool(result.trx_lists.has("trx_diamond_list")).is_false()
	assert_int(int(result.trx_diamond["paid_amount"])).is_equal(30)
	assert_int(result.trx_lists["trx_equipment_list"].size()).is_equal(1)
	assert_int(result.trx_lists["trx_stamina_list"].size()).is_equal(1)
	assert_int(result.login_bonuses.size()).is_equal(1)
	var bonus := result.login_bonuses[0]
	assert_str(bonus.type).is_equal("gold")
	assert_int(bonus.amount).is_equal(5000)
	assert_str(bonus.expire_at).is_empty()
	assert_dict(bonus.metadata).is_empty()
	assert_bool(bonus.has_grade()).is_false()


## 前提: 一覧のキーが null のもの・欠落しているもの・sys_player が null。操作: from_dict。
## 期待: 落ちずに、配列は []、辞書（trx_diamond を含む）は {} になる（null を型付きの変数に渡す事故を防ぐ。D3）。
func test_null_and_missing_are_treated_the_same() -> void:
	var response := LoginResponse.from_dict(
		{"sys_player": null, "trx_unit_list": null, "login_bonus_list": null}
	)
	assert_dict(response.sys_player).is_empty()
	assert_int(response.trx_lists.size()).is_equal(5)
	for key in response.trx_lists:
		assert_array(response.trx_lists[key]).is_empty()
	assert_array(response.login_bonus_list).is_empty()


## 前提: 空の辞書（全項目が欠落）。期待: 全部空で成功の結果になる。
func test_empty_body_gives_empty_success() -> void:
	var result := LoginResponse.from_dict({}).to_domain()
	assert_bool(result.ok).is_true()
	assert_dict(result.sys_player).is_empty()
	assert_array(result.login_bonuses).is_empty()


## 前提: metadata に grade がある受取と、is_paid だけの受取、壊れた要素。操作: from_dict。
## 期待: 壊れた要素は捨て、has_grade は grade キーがあるときだけ真（表示は「あるときだけ」。0 節 l）。
func test_metadata_grade_detection() -> void:
	var body := {
		"login_bonus_list":
		[
			{"unique_id": "1", "type": "unit", "id": "u", "amount": 1, "metadata": {"grade": 3}},
			{
				"unique_id": "2",
				"type": "gold",
				"id": "g",
				"amount": 1,
				"metadata": {"is_paid": true}
			},
			"壊れた要素",
		]
	}
	var bonuses := LoginResponse.from_dict(body).login_bonus_list
	assert_int(bonuses.size()).is_equal(2)
	assert_bool(bonuses[0].has_grade()).is_true()
	assert_bool(bonuses[1].has_grade()).is_false()


## 前提: trx_diamond が null・キー無し・型違い（旧形式の配列）。操作: from_dict。
## 期待: どれも空の辞書（有償ダイヤの行が無い = 0 として扱える）。
func test_trx_diamond_null_missing_or_wrong_type_is_empty() -> void:
	assert_dict(LoginResponse.from_dict({"trx_diamond": null}).trx_diamond).is_empty()
	assert_dict(LoginResponse.from_dict({}).trx_diamond).is_empty()
	(
		assert_dict(LoginResponse.from_dict({"trx_diamond": [{"paid_amount": 1}]}).trx_diamond)
		. is_empty()
	)


## 前提: 旧キー trx_diamond_list だけがある応答。操作: from_dict。
## 期待: 読まない（trx_diamond は空・trx_lists にも入らない）。
func test_legacy_trx_diamond_list_is_not_read() -> void:
	var response := LoginResponse.from_dict({"trx_diamond_list": [{"paid_amount": 99}]})
	assert_dict(response.trx_diamond).is_empty()
	assert_bool(response.trx_lists.has("trx_diamond_list")).is_false()


## 前提: trx_diamond がある応答。操作: to_domain。期待: 結果の trx_diamond に入る。
## offset は Date ヘッダー由来なので、本文からは作られない（既定の 0・無効）。
func test_to_domain_carries_trx_diamond_without_server_time() -> void:
	var result := LoginResponse.from_dict({"trx_diamond": {"paid_amount": 5}}).to_domain()
	assert_int(int(result.trx_diamond["paid_amount"])).is_equal(5)
	assert_int(result.server_time_offset_seconds).is_equal(0)
	assert_bool(result.has_server_time).is_false()
