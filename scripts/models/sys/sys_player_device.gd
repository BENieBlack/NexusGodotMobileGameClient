class_name SysPlayerDevice
extends RefCounted

# デバイス情報モデル

var id: int = 0
var sys_player_id: int = 0
var uuid: String = ""
var device_info: Dictionary = {}
var last_login_at: String = ""
var created_at: String = ""
var updated_at: String = ""

# JSONからインスタンスを生成
static func from_json(data: Dictionary) -> SysPlayerDevice:
	var device = SysPlayerDevice.new()
	
	if data.has("id"):
		device.id = int(data["id"])
	if data.has("sys_player_id"):
		device.sys_player_id = int(data["sys_player_id"])
	if data.has("uuid"):
		device.uuid = str(data["uuid"])
	if data.has("device_info"):
		device.device_info = data["device_info"] if typeof(data["device_info"]) == TYPE_DICTIONARY else {}
	if data.has("last_login_at"):
		device.last_login_at = str(data["last_login_at"])
	if data.has("created_at"):
		device.created_at = str(data["created_at"])
	if data.has("updated_at"):
		device.updated_at = str(data["updated_at"])
	
	return device

# インスタンスをDictionaryに変換
func to_dict() -> Dictionary:
	return {
		"id": id,
		"sys_player_id": sys_player_id,
		"uuid": uuid,
		"device_info": device_info,
		"last_login_at": last_login_at,
		"created_at": created_at,
		"updated_at": updated_at
	}

# デバイス情報の個別取得
func get_os() -> String:
	return device_info.get("os", "")

func get_os_version() -> String:
	return device_info.get("os_version", "")

func get_model() -> String:
	return device_info.get("model", "")

func get_app_version() -> String:
	return device_info.get("app_version", "")

# デバッグ用の文字列表現
func _to_string() -> String:
	return "SysPlayerDevice(id=%d, player_id=%d, uuid=%s)" % [id, sys_player_id, uuid]
