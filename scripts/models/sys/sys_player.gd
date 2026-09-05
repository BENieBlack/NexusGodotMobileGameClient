class_name SysPlayer
extends RefCounted

# プレイヤー基本情報モデル

var id: int = 0
var uuid: String = ""
var my_id: String = ""
var name: String = ""
var level: int = 1
var level_exp: int = 0
var last_login_at: String = ""
var created_at: String = ""
var updated_at: String = ""

# JSONからインスタンスを生成
static func from_json(data: Dictionary) -> SysPlayer:
	var player = SysPlayer.new()
	
	if data.has("id"):
		player.id = int(data["id"])
	if data.has("uuid"):
		player.uuid = str(data["uuid"])
	if data.has("my_id"):
		player.my_id = str(data["my_id"])
	if data.has("name"):
		player.name = str(data["name"])
	if data.has("level"):
		player.level = int(data["level"])
	if data.has("level_exp"):
		player.level_exp = int(data["level_exp"])
	if data.has("last_login_at"):
		player.last_login_at = str(data["last_login_at"])
	if data.has("created_at"):
		player.created_at = str(data["created_at"])
	if data.has("updated_at"):
		player.updated_at = str(data["updated_at"])
	
	return player

# インスタンスをDictionaryに変換
func to_dict() -> Dictionary:
	return {
		"id": id,
		"uuid": uuid,
		"my_id": my_id,
		"name": name,
		"level": level,
		"level_exp": level_exp,
		"last_login_at": last_login_at,
		"created_at": created_at,
		"updated_at": updated_at
	}

# デバッグ用の文字列表現
func _to_string() -> String:
	return "SysPlayer(id=%d, my_id=%s, name=%s, level=%d)" % [id, my_id, name, level]
