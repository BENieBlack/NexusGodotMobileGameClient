extends Node

# ユーザーデータ管理 - ログイン状態とユーザー情報を保存

const SAVE_PATH = "user://user_data.save"

var is_logged_in: bool = false
var auth_token: String = ""
var refresh_token: String = ""
var user_id: String = ""
# 所属ギルドID（0 = 未加入）
var guild_id: int = 0
var master_deploy_id: int = 0
var master_hash: String = ""
var user_data: Dictionary = {}

# ログイン後に取得するゲームデータ
var trx_unit_list: Array = []
var trx_item_list: Array = []
var trx_wallet_list: Array = []
var login_bonus_list: Array = []

signal user_data_loaded()

func _ready():
	load_user_data()

# ユーザーデータを保存
func save_user_data() -> void:
	var save_dict = {
		"auth_token": auth_token,
		"refresh_token": refresh_token,
		"user_id": user_id,
		"guild_id": guild_id,
		"master_deploy_id": master_deploy_id,
		"master_hash": master_hash,
		"user_data": user_data
	}

	var save_file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if save_file:
		save_file.store_var(save_dict)
		save_file.close()
		print("ユーザーデータを保存しました")
	else:
		print("ユーザーデータの保存に失敗しました")

# ユーザーデータを読み込み
func load_user_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		print("保存データが存在しません（新規ユーザー）")
		is_logged_in = false
		user_data_loaded.emit()
		return

	var save_file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if save_file:
		var save_dict = save_file.get_var()
		save_file.close()

		auth_token = save_dict.get("auth_token", "")
		refresh_token = save_dict.get("refresh_token", "")
		user_id = save_dict.get("user_id", "")
		guild_id = int(save_dict.get("guild_id", 0))
		master_deploy_id = int(save_dict.get("master_deploy_id", 0))
		master_hash = str(save_dict.get("master_hash", ""))
		user_data = save_dict.get("user_data", {})

		is_logged_in = auth_token != ""
		print("ユーザーデータを読み込みました: ", "ログイン済み" if is_logged_in else "未ログイン")
	else:
		print("ユーザーデータの読み込みに失敗しました")
		is_logged_in = false

	user_data_loaded.emit()

# 認証情報を設定（sign_up / sign_in 後に呼ぶ）
func set_auth_data(access_token: String, p_refresh_token: String, data: Dictionary) -> void:
	auth_token = access_token
	refresh_token = p_refresh_token
	user_data = data
	# IDは数値で返ってくる可能性があるのでstr()で文字列に変換
	if data.has("id"):
		user_id = str(data["id"])
	elif data.has("my_id"):
		user_id = str(data["my_id"])
	else:
		user_id = ""
	is_logged_in = true
	save_user_data()

# トークンのみ更新（リフレッシュ後に呼ぶ）
func update_tokens(new_access_token: String, new_refresh_token: String) -> void:
	auth_token = new_access_token
	if new_refresh_token != "":
		refresh_token = new_refresh_token
	save_user_data()

func set_master_deploy_id(deploy_id: int) -> void:
	master_deploy_id = deploy_id
	save_user_data()

func set_master_hash(hash_value: String) -> void:
	master_hash = hash_value
	save_user_data()

# ログイン後のゲームデータを設定（POST /auth/login のレスポンス）
func set_login_data(
	p_sys_player: Dictionary,
	p_trx_unit_list: Array,
	p_trx_item_list: Array,
	p_trx_wallet_list: Array,
	p_login_bonus_list: Array
) -> void:
	user_data = p_sys_player
	if p_sys_player.has("my_id"):
		user_id = str(p_sys_player["my_id"])
	trx_unit_list = p_trx_unit_list
	trx_item_list = p_trx_item_list
	trx_wallet_list = p_trx_wallet_list
	login_bonus_list = p_login_bonus_list
	print("ログインデータを保存しました: ユニット%d件, アイテム%d件, ウォレット%d件, ログインボーナス%d件" % [
		trx_unit_list.size(), trx_item_list.size(), trx_wallet_list.size(), login_bonus_list.size()
	])
	# 永続化はしない（セッションメモリのみ）

# ログアウト
func logout() -> void:
	auth_token = ""
	refresh_token = ""
	user_id = ""
	guild_id = 0
	master_deploy_id = 0
	master_hash = ""
	user_data = {}
	trx_unit_list = []
	trx_item_list = []
	trx_wallet_list = []
	login_bonus_list = []
	is_logged_in = false

	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

	print("ログアウトしました")

# 新規ユーザーかどうかを判定
func is_new_user() -> bool:
	return not is_logged_in
