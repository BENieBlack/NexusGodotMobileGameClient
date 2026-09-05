extends Control

# APIテスト画面 - 各種APIエンドポイントをテストするための画面

@onready var response_text: TextEdit = $MarginContainer/VBoxContainer/ScrollContainer/ResponseText
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel

var api_client: Node

func _ready():
	print("APIテスト画面を表示")
	
	# APIクライアントを作成
	api_client = load("res://scripts/services/api_client.gd").new()
	add_child(api_client)
	
	# シグナルを接続
	api_client.request_completed.connect(_on_api_request_completed)
	api_client.request_failed.connect(_on_api_request_failed)
	
	# 初期メッセージ
	_update_status("準備完了", false)
	_append_response("APIテスト画面")
	_append_response("認証状態: " + ("ログイン済み" if UserDataManager.is_logged_in else "未ログイン"))
	if UserDataManager.is_logged_in:
		_append_response("ユーザーID: " + str(UserDataManager.user_id))
		_append_response("トークン: " + UserDataManager.auth_token.substr(0, 30) + "...")
	_append_response("---")

# デバイスIDリセット
func _on_reset_device_button_pressed():
	_update_status("デバイスIDをリセット中...", false)
	_append_response("\n[デバイスIDリセット]")
	
	# AuthServiceのデバイスIDをリセット
	var auth_service = get_node("/root/AuthService")
	if auth_service and auth_service.has_method("reset_device_id"):
		auth_service.reset_device_id()
		_append_response("✓ デバイスIDをリセットしました")
		_append_response("次回のsign_upで新しいデバイスIDが生成されます")
	else:
		_append_response("✗ AuthServiceが見つかりません")
	
	_update_status("準備完了", false)

# プレイヤー情報取得
func _on_get_player_button_pressed():
	_update_status("プレイヤー情報取得中...", false)
	_append_response("\n[リクエスト] GET /player/me")
	api_client.get_request("/player/me")

# ガチャ実行
func _on_gacha_button_pressed():
	_update_status("ガチャ実行中...", false)
	_append_response("\n[リクエスト] POST /gacha/draw")
	var body = {
		"gacha_id": 1,
		"draw_count": 1
	}
	_append_response("パラメータ: " + JSON.stringify(body))
	api_client.post_request("/gacha/draw", body)

# 装備レベルアップ
func _on_equipment_levelup_button_pressed():
	_update_status("装備レベルアップ中...", false)
	_append_response("\n[リクエスト] POST /equipment/level_up")
	var body = {
		"equipment_id": 1,
		"level": 2
	}
	_append_response("パラメータ: " + JSON.stringify(body))
	api_client.post_request("/equipment/level_up", body)

# ユニットレベルアップ
func _on_unit_levelup_button_pressed():
	_update_status("ユニットレベルアップ中...", false)
	_append_response("\n[リクエスト] POST /unit/level_up")
	var body = {
		"unit_id": 1
	}
	_append_response("パラメータ: " + JSON.stringify(body))
	api_client.post_request("/unit/level_up", body)

# フレンドリスト取得
func _on_friend_list_button_pressed():
	_update_status("フレンドリスト取得中...", false)
	_append_response("\n[リクエスト] GET /friend/list")
	api_client.get_request("/friend/list")

# フレンド申請リスト取得
func _on_friend_apply_list_button_pressed():
	_update_status("フレンド申請リスト取得中...", false)
	_append_response("\n[リクエスト] GET /friend/apply/list")
	api_client.get_request("/friend/apply/list")

# メールボックスリスト取得
func _on_mailbox_list_button_pressed():
	_update_status("メールボックスリスト取得中...", false)
	_append_response("\n[リクエスト] GET /mailbox/list")
	api_client.get_request("/mailbox/list")

# バージョンチェック
func _on_version_check_button_pressed():
	_update_status("バージョンチェック中...", false)
	_append_response("\n[リクエスト] POST /auth/version")
	var body = {
		"client_version": "1.0.0"
	}
	_append_response("パラメータ: " + JSON.stringify(body))
	api_client.post_request("/auth/version", body)

# ログイン
func _on_login_button_pressed():
	_update_status("ログイン中...", false)
	_append_response("\n[リクエスト] POST /auth/login")
	var body = {}
	api_client.post_request("/auth/login", body)

# クリアボタン
func _on_clear_button_pressed():
	response_text.text = ""
	_append_response("クリアしました")
	_update_status("準備完了", false)

# 戻るボタン
func _on_back_button_pressed():
	get_tree().change_scene_to_file("res://scenes/title/title.tscn")

# APIリクエスト成功時
func _on_api_request_completed(response_data: Dictionary):
	_update_status("成功", false)
	_append_response("[レスポンス] 成功")
	_append_response(JSON.stringify(response_data, "  "))

# APIリクエスト失敗時
func _on_api_request_failed(error: String):
	_update_status("エラー: " + error, true)
	_append_response("[エラー] " + error)

# ステータスラベルを更新
func _update_status(message: String, is_error: bool):
	status_label.text = message
	if is_error:
		status_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	else:
		status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))

# レスポンステキストに追加
func _append_response(text: String):
	response_text.text += text + "\n"
	# 自動スクロール
	await get_tree().process_frame
	response_text.scroll_vertical = response_text.get_line_count()
