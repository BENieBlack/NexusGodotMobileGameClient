class_name SysPlayerToken
extends RefCounted

# リフレッシュトークン管理モデル

var id: int = 0
var sys_player_id: int = 0
var sys_player_device_id: int = 0
var refresh_token_hash: String = ""
var expires_at: String = ""
var revoked_at: String = ""
var created_at: String = ""
var updated_at: String = ""

# JSONからインスタンスを生成
static func from_json(data: Dictionary) -> SysPlayerToken:
	var token = SysPlayerToken.new()
	
	if data.has("id"):
		token.id = int(data["id"])
	if data.has("sys_player_id"):
		token.sys_player_id = int(data["sys_player_id"])
	if data.has("sys_player_device_id"):
		token.sys_player_device_id = int(data["sys_player_device_id"])
	if data.has("refresh_token_hash"):
		token.refresh_token_hash = str(data["refresh_token_hash"])
	if data.has("expires_at"):
		token.expires_at = str(data["expires_at"])
	if data.has("revoked_at") and data["revoked_at"] != null:
		token.revoked_at = str(data["revoked_at"])
	if data.has("created_at"):
		token.created_at = str(data["created_at"])
	if data.has("updated_at"):
		token.updated_at = str(data["updated_at"])
	
	return token

# インスタンスをDictionaryに変換
func to_dict() -> Dictionary:
	return {
		"id": id,
		"sys_player_id": sys_player_id,
		"sys_player_device_id": sys_player_device_id,
		"refresh_token_hash": refresh_token_hash,
		"expires_at": expires_at,
		"revoked_at": revoked_at,
		"created_at": created_at,
		"updated_at": updated_at
	}

# トークンが有効かチェック
func is_valid() -> bool:
	if revoked_at != "":
		return false
	
	# expires_atの形式: "2026-08-13 10:30:00"
	# 簡易的なチェック（本来はDateTimeパースが必要）
	return expires_at != ""

# デバッグ用の文字列表現
func _to_string() -> String:
	return "SysPlayerToken(id=%d, player_id=%d, expires_at=%s)" % [id, sys_player_id, expires_at]
