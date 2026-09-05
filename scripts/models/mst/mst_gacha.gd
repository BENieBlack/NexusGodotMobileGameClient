class_name MstGacha
extends RefCounted

# ガチャマスターモデル

var deploy_key: int = 202601010
var id: String = ""
var sort_desc: int = 0
var is_active: bool = true
var start_at: String = ""
var end_at: String = ""
var daily_limit: int = 0
var has_step_up: bool = false
var created_at: String = ""
var updated_at: String = ""

# 多言語データ（l10n）
var name: String = ""
var description: String = ""

# JSONからインスタンスを生成
static func from_json(data: Dictionary) -> MstGacha:
	var gacha = MstGacha.new()
	
	if data.has("deploy_key"):
		gacha.deploy_key = int(data["deploy_key"])
	if data.has("id"):
		gacha.id = str(data["id"])
	if data.has("sort_desc"):
		gacha.sort_desc = int(data["sort_desc"])
	if data.has("is_active"):
		gacha.is_active = bool(data["is_active"])
	if data.has("start_at") and data["start_at"] != null:
		gacha.start_at = str(data["start_at"])
	if data.has("end_at") and data["end_at"] != null:
		gacha.end_at = str(data["end_at"])
	if data.has("daily_limit"):
		gacha.daily_limit = int(data["daily_limit"])
	if data.has("has_step_up"):
		gacha.has_step_up = bool(data["has_step_up"])
	if data.has("created_at"):
		gacha.created_at = str(data["created_at"])
	if data.has("updated_at"):
		gacha.updated_at = str(data["updated_at"])
	
	# 多言語データ
	if data.has("name"):
		gacha.name = str(data["name"])
	if data.has("description"):
		gacha.description = str(data["description"])
	
	return gacha

# インスタンスをDictionaryに変換
func to_dict() -> Dictionary:
	return {
		"deploy_key": deploy_key,
		"id": id,
		"sort_desc": sort_desc,
		"is_active": is_active,
		"start_at": start_at,
		"end_at": end_at,
		"daily_limit": daily_limit,
		"has_step_up": has_step_up,
		"created_at": created_at,
		"updated_at": updated_at,
		"name": name,
		"description": description
	}

# ガチャが現在有効かチェック
func is_available() -> bool:
	if not is_active:
		return false
	
	# 簡易的なチェック（本来はDateTimeパースが必要）
	# start_at/end_atがnullの場合は常時利用可能
	return true

# デバッグ用の文字列表現
func _to_string() -> String:
	return "MstGacha(id=%s, name=%s, is_active=%s)" % [id, name, is_active]
