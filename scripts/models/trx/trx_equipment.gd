class_name TrxEquipment
extends RefCounted

# プレイヤー所持装備モデル

var id: int = 0
var sys_player_id: int = 0
var mst_equipment_id: String = ""
var grade: int = 1
var level: int = 1
var level_exp: int = 0
var is_delete: bool = false
var created_at: String = ""
var updated_at: String = ""

# マスターデータへの参照（オプション）
var master: MstEquipment = null

# JSONからインスタンスを生成
static func from_json(data: Dictionary) -> TrxEquipment:
	var equipment = TrxEquipment.new()
	
	if data.has("id"):
		equipment.id = int(data["id"])
	if data.has("sys_player_id"):
		equipment.sys_player_id = int(data["sys_player_id"])
	if data.has("mst_equipment_id"):
		equipment.mst_equipment_id = str(data["mst_equipment_id"])
	if data.has("grade"):
		equipment.grade = int(data["grade"])
	if data.has("level"):
		equipment.level = int(data["level"])
	if data.has("level_exp"):
		equipment.level_exp = int(data["level_exp"])
	if data.has("is_delete"):
		equipment.is_delete = bool(data["is_delete"])
	if data.has("created_at"):
		equipment.created_at = str(data["created_at"])
	if data.has("updated_at"):
		equipment.updated_at = str(data["updated_at"])
	
	# マスターデータが含まれている場合
	if data.has("master") and typeof(data["master"]) == TYPE_DICTIONARY:
		equipment.master = MstEquipment.from_json(data["master"])
	
	return equipment

# インスタンスをDictionaryに変換
func to_dict() -> Dictionary:
	var result = {
		"id": id,
		"sys_player_id": sys_player_id,
		"mst_equipment_id": mst_equipment_id,
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

# 装備名を取得（マスターデータがあれば）
func get_name() -> String:
	if master != null:
		return master.name
	return mst_equipment_id

# レアリティを取得（マスターデータがあれば）
func get_rarity_string() -> String:
	if master != null:
		return master.get_rarity_string()
	return "?"

# 現在のステータスを計算（レベル・グレード補正を考慮）
func get_current_attack() -> int:
	if master != null:
		return master.attack + (level - 1) * 5 + (grade - 1) * 10
	return 0

func get_current_defense() -> int:
	if master != null:
		return master.defense + (level - 1) * 5 + (grade - 1) * 10
	return 0

func get_current_hp() -> int:
	if master != null:
		return master.hp + (level - 1) * 10 + (grade - 1) * 20
	return 0

# デバッグ用の文字列表現
func _to_string() -> String:
	return "TrxEquipment(id=%d, mst_id=%s, grade=%d, level=%d)" % [id, mst_equipment_id, grade, level]
