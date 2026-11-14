## DiamondTotal と CoinAmount の単体テスト（client_design.md 4 節）。
extends GdUnitTestSuite


## 前提: 有償 30・暫定の無償 100・trx_item の free_diamond の free_amount 50。期待: 180。
func test_sums_paid_free_and_item() -> void:
	var diamond := {"paid_amount": 30, "free_amount": 100}
	var items := [{"mst_item_id": "free_diamond", "free_amount": 50, "paid_amount": 0}]
	assert_int(DiamondTotal.calculate(diamond, items)).is_equal(180)


## 前提: 新規ユーザー（trx_diamond なし・free_diamond 50）。期待: 50。
func test_initial_grant_only_in_item() -> void:
	var items := [{"mst_item_id": "free_diamond", "free_amount": 50}]
	assert_int(DiamondTotal.calculate({}, items)).is_equal(50)


## 前提: trx_item の paid_amount と他の mst_item_id の行。期待: 足さない（paid_amount と別アイテムは無視）。
func test_does_not_add_item_paid_amount_or_other_items() -> void:
	var diamond := {"paid_amount": 10}
	var items := [
		{"mst_item_id": "free_diamond", "free_amount": 5, "paid_amount": 999},
		{"mst_item_id": "gold", "free_amount": 777},
	]
	assert_int(DiamondTotal.calculate(diamond, items)).is_equal(15)


## 前提: free_amount のキー無し・null（暫定の項の廃止後）。期待: 0 扱いで有償だけ。
func test_free_amount_key_missing_or_null() -> void:
	assert_int(DiamondTotal.calculate({"paid_amount": 7}, [])).is_equal(7)
	assert_int(DiamondTotal.calculate({"paid_amount": 7, "free_amount": null}, [])).is_equal(7)


## 前提: 空・行なし。期待: 0。
func test_empty_is_zero() -> void:
	assert_int(DiamondTotal.calculate({}, [])).is_equal(0)


## 前提: 削除行（真偽値・1）。期待: 除く。0 の is_delete は有効。float の数量も整数になる。
func test_deleted_rows_are_excluded() -> void:
	var diamond := {"paid_amount": 20.0, "free_amount": 5, "is_delete": true}
	var items := [
		{"mst_item_id": "free_diamond", "free_amount": 40, "is_delete": 1},
		{"mst_item_id": "free_diamond", "free_amount": 3.0, "is_delete": 0},
	]
	assert_int(DiamondTotal.calculate(diamond, items)).is_equal(3)


## Coin: coin の行の free_amount だけ。paid_amount は足さない・他の行は見ない・行なしは 0・削除行は除く。
func test_coin_amount() -> void:
	var wallet := [
		{"mst_item_id": "coin", "free_amount": 1000.0, "paid_amount": 50},
		{"mst_item_id": "gold", "free_amount": 5},
		{"mst_item_id": "coin", "free_amount": 9, "is_delete": true},
	]
	assert_int(CoinAmount.calculate(wallet)).is_equal(1000)
	assert_int(CoinAmount.calculate([])).is_equal(0)
	assert_int(CoinAmount.calculate([{"mst_item_id": "gold", "free_amount": 1}])).is_equal(0)
