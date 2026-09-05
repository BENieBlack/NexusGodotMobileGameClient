class_name TrxUnit
extends RefCounted

# プレイヤー所持ユニットモデル

var id: int = 0
var sys_player_id: int = 0
var mst_unit_id: String = ""
var grade: int = 1
var level: int = 1
var level_exp: int = 0
var is_delete: bool = false
var created_at: String = ""
var updated_at: String = ""

# マスターデータへの参照（オプション）
var master: MstUnit = null

# JSONからインスタンスを生成
static func from_json(data: Dictionary) -> TrxUnit:
	var unit = TrxUnit.new()
	
	if data.has("id"):
		unit.id = int(data["id"])
	if data.has("sys_player_id"):
		unit.sys_player_id = int(data["sys_player_id"])
	if data.has("mst_unit_id"):
		unit.mst_unit_id = str(data["mst_unit_id"])
	if data.has("grade"):
		unit.grade = int(data["grade"])
	if data.has("level"):
		unit.level = int(data["level"])
	if data.has("level_exp"):
		unit.level_exp = int(data["level_exp"])
	if data.has("is_delete"):
		unit.is_delete = bool(data["is_delete"])
	if data.has("created_at"):
		unit.created_at = str(data["created_at"])
	if data.has("updated_at"):
		unit.updated_at = str(data["updated_at"])
	
	# マスターデータが含まれている場合
	if data.has("master") and typeof(data["master"]) == TYPE_DICTIONARY:
		unit.master = MstUnit.from_json(data["master"])
	
	return unit

# インスタンスをDictionaryに変換
func to_dict() -> Dictionary:
	var result = {
		"id": id,
		"sys_player_id": sys_player_id,
		"mst_unit_id": mst_unit_id,
		"grade": grade,
		"level": level,
		"level_exp": level_exp,
		"is_delete": is_delete,
		"created_at": created_at,
		"updated_at": updated_at
	}
	
	if master != null:
		result["master"] = master.to_dict()
	
	return result

# ユニット名を取得（マスターデータがあれば）
func get_name() -> String:
	if master != null:
		return master.name
	return mst_unit_id

# レアリティを取得（マスターデータがあれば）
func get_rarity_string() -> String:
	if master != null:
		return master.get_rarity_string()
	return "?"

# デバッグ用の文字列表現
func _to_string() -> String:
	return "TrxUnit(id=%d, mst_id=%s, grade=%d, level=%d)" % [id, mst_unit_id, grade, level]
