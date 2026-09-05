class_name TrxGachaHistory
extends RefCounted

# ガチャ実行履歴モデル

enum CostType { DIAMOND, PAID_DIAMOND, ITEM }

var id: int = 0
var sys_player_id: int = 0
var mst_gacha_id: String = ""
var draw_count: int = 1
var cost_type: CostType = CostType.DIAMOND
var cost_id: String = ""
var cost_amount: int = 0
var prizes: Array = []  # Array of Dictionary
var is_delete: bool = false
var created_at: String = ""
var updated_at: String = ""

# JSONからインスタンスを生成
static func from_json(data: Dictionary) -> TrxGachaHistory:
	var history = TrxGachaHistory.new()
	
	if data.has("id"):
		history.id = int(data["id"])
	if data.has("sys_player_id"):
		history.sys_player_id = int(data["sys_player_id"])
	if data.has("mst_gacha_id"):
		history.mst_gacha_id = str(data["mst_gacha_id"])
	if data.has("draw_count"):
		history.draw_count = int(data["draw_count"])
	if data.has("cost_type"):
		history.cost_type = _parse_cost_type(str(data["cost_type"]))
	if data.has("cost_id") and data["cost_id"] != null:
		history.cost_id = str(data["cost_id"])
	if data.has("cost_amount"):
		history.cost_amount = int(data["cost_amount"])
	if data.has("prizes") and typeof(data["prizes"]) == TYPE_ARRAY:
		history.prizes = data["prizes"]
	if data.has("is_delete"):
		history.is_delete = bool(data["is_delete"])
	if data.has("created_at"):
		history.created_at = str(data["created_at"])
	if data.has("updated_at"):
		history.updated_at = str(data["updated_at"])
	
	return history

# 文字列からCostTypeに変換
static func _parse_cost_type(type_str: String) -> CostType:
	match type_str:
		"diamond": return CostType.DIAMOND
		"paid_diamond": return CostType.PAID_DIAMOND
		"item": return CostType.ITEM
		_: return CostType.DIAMOND

# CostTypeを文字列に変換
func get_cost_type_string() -> String:
	match cost_type:
		CostType.DIAMOND: return "diamond"
		CostType.PAID_DIAMOND: return "paid_diamond"
		CostType.ITEM: return "item"
		_: return "diamond"

# インスタンスをDictionaryに変換
func to_dict() -> Dictionary:
	return {
		"id": id,
		"sys_player_id": sys_player_id,
		"mst_gacha_id": mst_gacha_id,
		"draw_count": draw_count,
		"cost_type": get_cost_type_string(),
		"cost_id": cost_id,
		"cost_amount": cost_amount,
		"prizes": prizes,
		"is_delete": is_delete,
		"created_at": created_at,
		"updated_at": updated_at
	}

# 獲得景品の数を取得
func get_prize_count() -> int:
	return prizes.size()

# 指定したレアリティの景品数を取得
func count_prizes_by_rarity(rarity: String) -> int:
	var count = 0
	for prize in prizes:
		if typeof(prize) == TYPE_DICTIONARY and prize.get("rarity", "") == rarity:
			count += 1
	return count

# デバッグ用の文字列表現
func _to_string() -> String:
	return "TrxGachaHistory(id=%d, gacha_id=%s, draw_count=%d, prizes=%d)" % [id, mst_gacha_id, draw_count, get_prize_count()]
