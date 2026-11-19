## ItemIcon（アイコンの共通部品。client_design.md 5-2）のテスト。シーンを作って setup する。
## 守るもの: どの入力でも texture が入る（空表示・エラーにならない）、フォールバックの結果が絵に反映される、大きさが反映される。
extends GdUnitTestSuite

const ICON_SCENE := "res://core/presentation/item_icon/item_icon.tscn"


func _make() -> ItemIcon:
	var icon: ItemIcon = load(ICON_SCENE).instantiate()
	add_child(auto_free(icon))
	return icon


## 前提: 在る ID（coin）。操作: setup。期待: その ID の絵が入り、大きさが反映される。
func test_known_id_shows_its_icon() -> void:
	var icon := _make()
	icon.setup("item", "coin", "currency", 80)
	assert_str(icon.resolved_key).is_equal("items/coin")
	assert_object(icon.texture).is_same(ItemIconTable.texture_of("items/coin"))
	assert_vector(icon.custom_minimum_size).is_equal(Vector2(80, 80))


## 前提: 存在しない ID で mst_item.type は recovery。期待: カテゴリの絵（エラーにならない）。
func test_unknown_id_with_type_shows_category_icon() -> void:
	var icon := _make()
	icon.setup("item", "item_heal_999", "recovery", 56)
	assert_str(icon.resolved_key).is_equal("fallback/category_recovery")
	assert_object(icon.texture).is_not_null()


## 前提: 存在しない ID・マスターが引けない（type 空）。期待: unknown の絵。
func test_unknown_id_without_type_shows_unknown() -> void:
	var icon := _make()
	icon.setup("item", "nope", "", 48)
	assert_str(icon.resolved_key).is_equal("fallback/unknown")
	assert_object(icon.texture).is_same(ItemIconTable.texture_of("fallback/unknown"))


## 前提: unit・equipment・空の type・空の ID（枠のアイコンは対象外）。期待: どれも絵が入る（unknown）。
func test_non_item_types_and_empty_input_never_blank() -> void:
	var icon := _make()
	for type in ["unit", "equipment", "stamina", "paid_diamond", ""]:
		icon.setup(type, "coin", "", 48)
		assert_object(icon.texture).is_not_null()
		assert_str(icon.resolved_key).is_equal("fallback/unknown")
	icon.setup("item", "", "", 48)
	assert_object(icon.texture).is_not_null()


## 前提: setup を呼ぶ前に ItemIcon をツリーへ入れた後でも呼べる。期待: 再 setup で絵が切り替わる。
func test_setup_again_replaces_texture() -> void:
	var icon := _make()
	icon.setup("item", "coin", "", 48)
	icon.setup("item", "gold", "", 48)
	assert_str(icon.resolved_key).is_equal("items/gold")
