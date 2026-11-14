## DiamondTotal と CoinAmount の単体テスト（home-player-info 4 節。free-diamond-item 2 節で暫定項を削除）。
extends GdUnitTestSuite


## 前提: 有償 30・free_diamond 50。期待: 80（有償 + 無償の 2 経路だけ）。
func test_sums_paid_and_free_diamond_item() -> void:
	var items := [{"mst_item_id": "free_diamond", "free_amount": 50, "paid_amount": 0}]
	assert_int(DiamondTotal.calculate({"paid_amount": 30}, items)).is_equal(80)


## 前提: trx_diamond が空（null と同じ）・free_diamond 50。期待: 50（有償 0 で無償だけ出る）。
func test_trx_diamond_empty_shows_item_only() -> void:
	var items := [{"mst_item_id": "free_diamond", "free_amount": 50}]
	assert_int(DiamondTotal.calculate({}, items)).is_equal(50)


## 前提: trx_diamond だけ（free_diamond の行なし）。期待: 有償だけ。
func test_paid_only_without_free_diamond_row() -> void:
	assert_int(DiamondTotal.calculate({"paid_amount": 12}, [])).is_equal(12)


## 前提: trx_diamond に旧キー free_amount 100 が付いている（旧サーバー・誤配信）。
## 期待: 足さない（有償 7 のまま）。無償を trx_item に集約したので、二重に数える回帰を防ぐ。
func test_ignores_legacy_free_amount_key() -> void:
	assert_int(DiamondTotal.calculate({"paid_amount": 7, "free_amount": 100}, [])).is_equal(7)
	var items := [{"mst_item_id": "free_diamond", "free_amount": 5}]
	assert_int(DiamondTotal.calculate({"paid_amount": 7, "free_amount": 100}, items)).is_equal(12)


## 前提: free_diamond の行が free_amount 0 で残っている（使い切った後）。期待: 0 加算（有償だけ）。
func test_free_diamond_row_with_zero_amount() -> void:
	var items := [{"mst_item_id": "free_diamond", "free_amount": 0}]
	assert_int(DiamondTotal.calculate({"paid_amount": 30}, items)).is_equal(30)
	assert_int(DiamondTotal.calculate({}, items)).is_equal(0)


## 前提: trx_item の paid_amount と他の mst_item_id の行。期待: 足さない（paid_amount と別アイテムは無視）。
func test_does_not_add_item_paid_amount_or_other_items() -> void:
	var diamond := {"paid_amount": 10}
	var items := [
		{"mst_item_id": "free_diamond", "free_amount": 5, "paid_amount": 999},
		{"mst_item_id": "gold", "free_amount": 777},
	]
	assert_int(DiamondTotal.calculate(diamond, items)).is_equal(15)


## 前提: 空・行なし。期待: 0。
func test_empty_is_zero() -> void:
	assert_int(DiamondTotal.calculate({}, [])).is_equal(0)


## 前提: 削除行（真偽値・1）。期待: trx_diamond・free_diamond とも除く。0 の is_delete は有効。float も整数になる。
func test_deleted_rows_are_excluded() -> void:
	var diamond := {"paid_amount": 20.0, "is_delete": true}
	var items := [
		{"mst_item_id": "free_diamond", "free_amount": 40, "is_delete": 1},
		{"mst_item_id": "free_diamond", "free_amount": 3.0, "is_delete": 0},
	]
	assert_int(DiamondTotal.calculate(diamond, items)).is_equal(3)


## 前提: 数量が null。期待: 落ちずに 0 扱い。
func test_null_amounts_do_not_crash() -> void:
	var items := [{"mst_item_id": "free_diamond", "free_amount": null}]
	assert_int(DiamondTotal.calculate({"paid_amount": null}, items)).is_equal(0)


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
