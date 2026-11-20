## アイコンの「絵のキー」を決める純粋関数（client_design.md 5-2、要件 I5・I9）。
##
## 目的: 報酬・所持品の 1 件（type・id）から、どの絵を出すかを 1 か所で決める。画面ごとに
##       フォールバックの順を書かないための共通の規則。
## 流れ（resolve_key）:
##   1. type が item・wallet のときだけ、ID の絵 `items/<id>` を探す（在ればそれ）
##   2. 無ければ、mst_item の type（例 recovery）のカテゴリの絵 `fallback/category_<type>` を探す
##   3. どれも無ければ `fallback/unknown`（どの段でも例外・空表示にしない）
## 置き場の理由: Node・Texture2D に依存しない純粋関数なので domain（D2）。絵が実在するかは、呼び出し側が
##   述語（Callable）で渡す（core/domain は preload したアセットを知らない。実際の述語は ItemIconTable.has_key）。
class_name ItemIconResolver
extends RefCounted

## ID の絵のキーの頭（assets/icons/items/<mst_item.id>.svg）
const ITEMS_PREFIX := "items/"
## カテゴリの絵のキーの頭（assets/icons/fallback/category_<mst_item.type>.svg）
const CATEGORY_PREFIX := "fallback/category_"
## 最後の砦の絵のキー（assets/icons/fallback/unknown.svg）
const UNKNOWN_KEY := "fallback/unknown"
## ID で絵を引く type（報酬の type。wallet は mst_item.is_wallet の行で、gold などへの読み替えは持たない）
const ID_LOOKUP_TYPES: Array[String] = ["item", "wallet"]


## 絵のキーを返す。
## type: 報酬の種類（item / wallet / unit / equipment / stamina / paid_diamond など）。
##       item・wallet 以外は、枠のアイコン（対象外・I11）や mst_item の行でないもの（stamina）なので ID を引かず unknown にする
##       （`items/` に同じ ID の絵があっても使わない）
## id: mst_item.id（空なら ID の絵は探さない）
## mst_item_type: 引けた mst_item.type。マスターが引けなければ空（カテゴリの絵は探さない）
## exists: `func(key: String) -> bool`。その絵が在るか
static func resolve_key(
	type: String, id: String, mst_item_type: String, exists: Callable
) -> String:
	# --- 1. item・wallet 以外は、ID もカテゴリも引かずに unknown ---
	if not ID_LOOKUP_TYPES.has(type):
		return UNKNOWN_KEY
	# --- 2. ID の絵 ---
	if id != "" and exists.call(ITEMS_PREFIX + id):
		return ITEMS_PREFIX + id
	# --- 3. カテゴリの絵（マスターから type が引けたときだけ） ---
	if mst_item_type != "" and exists.call(CATEGORY_PREFIX + mst_item_type):
		return CATEGORY_PREFIX + mst_item_type
	# --- 4. 最後の砦 ---
	return UNKNOWN_KEY
