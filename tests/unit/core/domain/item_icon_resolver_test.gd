## ItemIconResolver（絵のキーの決定。client_design.md 5-2・9 節 V2）のテスト。
## 絵が実在するかは述語（Callable）で渡すので、テストでは「在るキーの集合」から作った偽の述語を使う。
## 守るもの: フォールバックの順（ID → カテゴリ → unknown）、対象外の type は ID を引かない、どの入力でも空にならない。
extends GdUnitTestSuite


## 在るキーの集合から、述語（key → bool）を作る。
func _exists(keys: Array[String]) -> Callable:
	return func(key: String) -> bool: return keys.has(key)


## 前提: items/coin が在る。操作: type=item・id=coin。期待: そのキー（ID の絵が最優先）。
func test_item_with_icon_returns_item_key() -> void:
	var exists := _exists(["items/coin", "fallback/category_currency", "fallback/unknown"])
	assert_str(ItemIconResolver.resolve_key("item", "coin", "currency", exists)).is_equal(
		"items/coin"
	)


## 前提: wallet は mst_item.is_wallet の行（gold など）。期待: item と同じく ID で引く。
func test_wallet_type_is_looked_up_by_id() -> void:
	var exists := _exists(["items/gold"])
	assert_str(ItemIconResolver.resolve_key("wallet", "gold", "", exists)).is_equal("items/gold")


## 前提: ID の絵が無く、mst_item.type=recovery が分かる。期待: カテゴリの絵。
func test_missing_item_icon_falls_back_to_category() -> void:
	var exists := _exists(["fallback/category_recovery"])
	assert_str(ItemIconResolver.resolve_key("item", "item_heal_999", "recovery", exists)).is_equal(
		"fallback/category_recovery"
	)


## 前提: ID の絵もカテゴリの絵も無い。期待: unknown。
func test_missing_both_falls_back_to_unknown() -> void:
	var exists := _exists(["items/coin"])
	assert_str(ItemIconResolver.resolve_key("item", "nope", "recovery", exists)).is_equal(
		"fallback/unknown"
	)


## 前提: マスターが引けず mst_item_type が空。期待: カテゴリは探さず unknown（`fallback/category_` を空の type で引かない）。
func test_empty_mst_item_type_skips_category() -> void:
	var exists := _exists(["fallback/category_"])
	assert_str(ItemIconResolver.resolve_key("item", "nope", "", exists)).is_equal(
		"fallback/unknown"
	)


## 前提: unit・equipment・stamina・paid_diamond・未知の type。ここでは items/ に同じ ID の絵も在る。
## 期待: どれも unknown（枠のアイコンは対象外 I11・stamina は mst_item の行でない。ID の絵があっても引かない）。
func test_non_item_types_always_unknown() -> void:
	var exists := _exists(["items/coin", "items/stamina_50", "fallback/category_currency"])
	for type in ["unit", "equipment", "stamina", "paid_diamond", "something_new", ""]:
		assert_str(ItemIconResolver.resolve_key(type, "coin", "currency", exists)).is_equal(
			"fallback/unknown"
		)


## 前提: id が空。期待: items/ は探さず（`items/` を引かない）、カテゴリが在ればそれ、無ければ unknown。
func test_empty_id() -> void:
	var exists := _exists(["items/", "fallback/category_points"])
	assert_str(ItemIconResolver.resolve_key("item", "", "points", exists)).is_equal(
		"fallback/category_points"
	)
	assert_str(ItemIconResolver.resolve_key("item", "", "", exists)).is_equal("fallback/unknown")


## 前提: 述語が全て偽（絵が 1 枚も無い）。期待: 常に unknown が返り、空文字にならない。
func test_all_false_predicate_returns_unknown() -> void:
	var none := func(_key: String) -> bool: return false
	for type in ["item", "wallet", "unit", ""]:
		assert_str(ItemIconResolver.resolve_key(type, "coin", "currency", none)).is_equal(
			"fallback/unknown"
		)
