## ItemIconTable（生成物。キー → preload した絵。client_design.md 5-3）のテスト。
## 守るもの: 全キーの絵が実在する（preload が通っている）、必須のキー（unknown・stamp・mst_item の全 29 行・
## 9 種類のカテゴリ）が在る、無いキーは null（has_key が偽）。
extends GdUnitTestSuite

## mst_item の全 29 行（サーバーの MstItemSeeder から転記。generate_icons.py の ITEMS と同じ二重管理）
const MST_ITEM_IDS: Array[String] = [
	"item_heal_001",
	"item_heal_002",
	"item_heal_003",
	"item_boost_001",
	"item_boost_002",
	"item_boost_003",
	"item_exp_001",
	"item_exp_002",
	"item_exp_003",
	"unit_exp_100",
	"unit_exp_1000",
	"unit_exp_10000",
	"unit_exp_100000",
	"item_material_001",
	"item_material_002",
	"item_material_003",
	"gold",
	"coin",
	"stamina_50",
	"free_diamond",
	"food",
	"wood",
	"stone",
	"iron",
	"alliance_points",
	"pvp_points",
	"event_points",
	"achievement_points",
	"vip_points",
]  # gdlint:ignore = max-line-length
## mst_item.type の 9 種類
const CATEGORIES: Array[String] = [
	"recovery",
	"boost",
	"experience",
	"unit_enhancement",
	"material",
	"currency",
	"stamina",
	"natural_resource",
	"points",
]


## 前提: 生成された表。期待: 全キーが has_key で真・texture_of が null でない（preload の実在。空の絵を持たない）。
func test_every_key_has_a_texture() -> void:
	assert_int(ItemIconTable.keys().size()).is_greater(0)
	for key: String in ItemIconTable.keys():
		assert_bool(ItemIconTable.has_key(key)).is_true()
		assert_object(ItemIconTable.texture_of(key)).is_not_null()


## 前提: 最後の砦とスタンプ。期待: 必ず在る（unknown が無いとフォールバックが空になる）。
func test_unknown_and_stamp_exist() -> void:
	assert_bool(ItemIconTable.has_key("fallback/unknown")).is_true()
	assert_bool(ItemIconTable.has_key("ui/stamp_check")).is_true()


## 前提: mst_item の全 29 行。期待: ID の絵が全部在る（足し忘れの検出。マスターが増えたらここも直す）。
func test_every_mst_item_id_has_an_icon() -> void:
	for item_id in MST_ITEM_IDS:
		assert_bool(ItemIconTable.has_key("items/" + item_id)).is_true()


## 前提: mst_item.type の 9 種類。期待: カテゴリの絵が全部在る。
func test_every_category_has_a_fallback() -> void:
	for category in CATEGORIES:
		assert_bool(ItemIconTable.has_key("fallback/category_" + category)).is_true()


## 前提: 存在しないキー・空文字。期待: has_key は偽・texture_of は null（呼び出し側が先に確かめる契約）。
func test_unknown_key_is_absent() -> void:
	assert_bool(ItemIconTable.has_key("items/no_such_item")).is_false()
	assert_bool(ItemIconTable.has_key("")).is_false()
	assert_object(ItemIconTable.texture_of("items/no_such_item")).is_null()
