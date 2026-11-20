## アイコンの読み込み表（生成物。手で編集しない）。
##
## 生成: tools/icons/generate_icons.py（make icons）。キー（例 `items/coin`）→ `preload` した Texture2D。
## 目的: アイコンを動的なパス（`"res://...%s" % id` の `load`）で読まず、`preload` の定数表から引く。
##       `preload` の実在はスクリプトの読み込み時に検査され（make check-release でも通る）、
##       書き出し（実機ビルド）の設定にも依存しない（client_design.md 5-3）。
## 使い方: `ItemIconTable.has_key(key)` で在るか、`ItemIconTable.texture_of(key)` で絵を引く。
##         在るかどうかの述語は ItemIconResolver に渡す（core/domain は Texture2D を知らない）。
class_name ItemIconTable
extends RefCounted

## キー → 絵。キーは `items/<mst_item.id>`・`fallback/category_<type>`・`fallback/unknown`・`ui/stamp_check`
const TEXTURES := {
	"items/item_heal_001": preload("res://assets/icons/items/item_heal_001.svg"),
	"items/item_heal_002": preload("res://assets/icons/items/item_heal_002.svg"),
	"items/item_heal_003": preload("res://assets/icons/items/item_heal_003.svg"),
	"items/item_boost_001": preload("res://assets/icons/items/item_boost_001.svg"),
	"items/item_boost_002": preload("res://assets/icons/items/item_boost_002.svg"),
	"items/item_boost_003": preload("res://assets/icons/items/item_boost_003.svg"),
	"items/item_exp_001": preload("res://assets/icons/items/item_exp_001.svg"),
	"items/item_exp_002": preload("res://assets/icons/items/item_exp_002.svg"),
	"items/item_exp_003": preload("res://assets/icons/items/item_exp_003.svg"),
	"items/unit_exp_100": preload("res://assets/icons/items/unit_exp_100.svg"),
	"items/unit_exp_1000": preload("res://assets/icons/items/unit_exp_1000.svg"),
	"items/unit_exp_10000": preload("res://assets/icons/items/unit_exp_10000.svg"),
	"items/unit_exp_100000": preload("res://assets/icons/items/unit_exp_100000.svg"),
	"items/item_material_001": preload("res://assets/icons/items/item_material_001.svg"),
	"items/item_material_002": preload("res://assets/icons/items/item_material_002.svg"),
	"items/item_material_003": preload("res://assets/icons/items/item_material_003.svg"),
	"items/gold": preload("res://assets/icons/items/gold.svg"),
	"items/coin": preload("res://assets/icons/items/coin.svg"),
	"items/stamina_50": preload("res://assets/icons/items/stamina_50.svg"),
	"items/free_diamond": preload("res://assets/icons/items/free_diamond.svg"),
	"items/food": preload("res://assets/icons/items/food.svg"),
	"items/wood": preload("res://assets/icons/items/wood.svg"),
	"items/stone": preload("res://assets/icons/items/stone.svg"),
	"items/iron": preload("res://assets/icons/items/iron.svg"),
	"items/alliance_points": preload("res://assets/icons/items/alliance_points.svg"),
	"items/pvp_points": preload("res://assets/icons/items/pvp_points.svg"),
	"items/event_points": preload("res://assets/icons/items/event_points.svg"),
	"items/achievement_points": preload("res://assets/icons/items/achievement_points.svg"),
	"items/vip_points": preload("res://assets/icons/items/vip_points.svg"),
	"fallback/category_recovery": preload("res://assets/icons/fallback/category_recovery.svg"),
	"fallback/category_boost": preload("res://assets/icons/fallback/category_boost.svg"),
	"fallback/category_experience": preload("res://assets/icons/fallback/category_experience.svg"),
	"fallback/category_unit_enhancement":
	preload("res://assets/icons/fallback/category_unit_enhancement.svg"),
	"fallback/category_material": preload("res://assets/icons/fallback/category_material.svg"),
	"fallback/category_currency": preload("res://assets/icons/fallback/category_currency.svg"),
	"fallback/category_stamina": preload("res://assets/icons/fallback/category_stamina.svg"),
	"fallback/category_natural_resource":
	preload("res://assets/icons/fallback/category_natural_resource.svg"),
	"fallback/category_points": preload("res://assets/icons/fallback/category_points.svg"),
	"fallback/unknown": preload("res://assets/icons/fallback/unknown.svg"),
	"ui/stamp_check": preload("res://assets/icons/ui/stamp_check.svg"),
}


## キーの絵が在るか。
static func has_key(key: String) -> bool:
	return TEXTURES.has(key)


## キーの絵を返す。無いキーは null（呼び出し側は先に has_key で確かめる。ItemIcon は必ず unknown へ落とす）。
static func texture_of(key: String) -> Texture2D:
	return TEXTURES.get(key, null)


## 全キー（確認用の一覧画面・テストが使う。表の順）。
static func keys() -> Array:
	return TEXTURES.keys()
