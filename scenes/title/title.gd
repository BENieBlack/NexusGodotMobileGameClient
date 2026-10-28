extends Control

# タイトル画面 - 自動的に認証 → ログイン → ログインボーナス画面へ遷移

@onready var title_label: Label = $CenterContainer/PanelContainer/VBoxContainer/TitleBg/TitleLabel
@onready var status_label: Label = $CenterContainer/PanelContainer/VBoxContainer/StatusLabel

var auth_service: Node
var api_client: Node

func _ready():
	print("タイトル画面を表示")
	title_label.text = "Mobile RPG"
	status_label.text = "認証中..."

	# AuthServiceを作成
	auth_service = preload("res://scripts/services/auth_service.gd").new()
	add_child(auth_service)

	# APIクライアントを作成（/auth/login 呼び出し用）
	api_client = preload("res://scripts/services/api_client.gd").new()
	add_child(api_client)

	# 認証完了・失敗シグナルを接続
	auth_service.auth_completed.connect(_on_auth_completed)
	auth_service.auth_failed.connect(_on_auth_failed)

	# ログインAPIのシグナルを接続
	api_client.request_completed.connect(_on_login_completed)
	api_client.request_failed.connect(_on_login_failed)
	api_client.business_error.connect(_on_login_business_error)

	# ユーザーデータが読み込まれたら認証開始
	if UserDataManager.user_data_loaded.is_connected(_start_authentication):
		_start_authentication()
	else:
		UserDataManager.user_data_loaded.connect(_start_authentication)
		if UserDataManager.is_logged_in or not FileAccess.file_exists("user://user_data.save"):
			_start_authentication()

# 認証処理を開始
func _start_authentication() -> void:
	# 二重呼び出し防止のため切断
	if UserDataManager.user_data_loaded.is_connected(_start_authentication):
		UserDataManager.user_data_loaded.disconnect(_start_authentication)

	await get_tree().create_timer(0.5).timeout  # タイトル画面を少し表示

	if UserDataManager.is_new_user():
		print("新規ユーザー - サインアップ実行")
		status_label.text = "新規登録中..."
		auth_service.sign_up()
	else:
		print("既存ユーザー - サインイン実行")
		status_label.text = "ログイン中..."
		auth_service.sign_in()

# 認証成功時 (sign_up / sign_in 完了)
func _on_auth_completed(access_token: String, p_refresh_token: String, user_data: Dictionary) -> void:
	print("認証完了")
	status_label.text = "ゲームデータを取得中..."

	# ユーザーデータを保存
	UserDataManager.set_auth_data(access_token, p_refresh_token, user_data)
	await MasterDataManager.check_and_update()

	# ログインAPI呼び出し（ログインボーナス取得、所持データ取得）
	api_client.post_request("/auth/login", {})

# ログインAPI成功時
func _on_login_completed(response_data: Dictionary) -> void:
	print("ログイン完了: ", response_data.keys())

	var sys_player = response_data.get("sys_player", {})
	var trx_unit_list = response_data.get("trx_unit_list", [])
	var trx_item_list = response_data.get("trx_item_list", [])
	var trx_wallet_list = response_data.get("trx_wallet_list", [])
	var login_bonus_list = response_data.get("login_bonus_list", [])

	UserDataManager.set_login_data(sys_player, trx_unit_list, trx_item_list, trx_wallet_list, login_bonus_list)

	status_label.text = "ログイン成功!"
	await get_tree().create_timer(0.5).timeout
	SceneManager.goto_agreement()

# ログインAPI失敗時
func _on_login_failed(error: String) -> void:
	print("ログインAPI失敗: ", error)
	# ログインボーナスが取得できなくてもホーム画面へ進む
	status_label.text = "ログイン成功（データ取得失敗）"
	await get_tree().create_timer(0.5).timeout
	SceneManager.goto_home()

# ログインAPIビジネスエラー時
func _on_login_business_error(error_code: int, message: String) -> void:
	print("ログインビジネスエラー (", error_code, "): ", message)
	# バージョン不一致など致命的なエラーはここで処理
	status_label.text = "エラー: " + message

# 認証失敗時
func _on_auth_failed(error: String) -> void:
	print("認証失敗: ", error)
	status_label.text = "エラー: " + error

# APIテストボタンが押された時
func _on_api_test_button_pressed() -> void:
	print("APIテスト画面へ遷移")
	get_tree().change_scene_to_file("res://scenes/api_test/api_test.tscn")
