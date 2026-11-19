## API テスト画面（デバッグ専用）。各エンドポイントを手で叩いて応答を見る。
##
## 目的: 開発中に API を 1 つずつ試す。製品ではない（debug/ はエクスポートから除外する。architecture.md 9 節）。
## 起動: タイトル・ホームからは開けない。直接開く: godot --path . res://debug/api_test/api_test.tscn
##       （認証は「認証」ボタンで行う。トークンは画面に出さない）
## 旧実装からの変更: ApiClient を自分で new せず、AppContext の 1 インスタンスを使う（signal を await に置き換えた。
##       機能は変えていない）。device_id のリセットは AppContext.debug_auth_token_repository() 経由。
extends Control

@onready var response_text: TextEdit = $MarginContainer/VBoxContainer/ScrollContainer/ResponseText
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel
@onready var buttons_grid: GridContainer = $MarginContainer/VBoxContainer/ButtonsGrid


func _ready() -> void:
	# 認証のボタンは、タイトルを経由せずに直接開いたときのために、コードで足す
	var auth_button := Button.new()
	auth_button.text = "認証 (sign_in/sign_up)"
	auth_button.pressed.connect(_on_auth_button_pressed)
	buttons_grid.add_child(auth_button)
	_update_status("準備完了", false)
	_append_response("APIテスト画面 (API: %s)" % ApiConfig.api_base_url())
	_append_response("---")


## 認証（sign_in / sign_up の振り分けは UseCase）
func _on_auth_button_pressed() -> void:
	_update_status("認証中...", false)
	var result := await AppContext.authenticate_use_case().handle()
	if result.ok:
		_update_status("成功", false)
		_append_response("[認証] 成功")
	else:
		_report_error(result.error)


## デバイスIDリセット（新しい UUID が次の sign_up で使われる）
func _on_reset_device_button_pressed() -> void:
	AppContext.debug_auth_token_repository().reset_device_id()
	_append_response("\n[デバイスIDリセット] 完了。次の sign_up で新しいデバイスIDが生成されます")
	_update_status("準備完了", false)


func _on_get_player_button_pressed() -> void:
	await _call_api("POST", "/player/me")


func _on_gacha_button_pressed() -> void:
	await _call_api("POST", "/gacha/draw", {"gacha_id": 1, "draw_count": 1})


func _on_equipment_levelup_button_pressed() -> void:
	await _call_api("POST", "/equipment/level_up", {"equipment_id": 1, "level": 2})


func _on_unit_levelup_button_pressed() -> void:
	await _call_api("POST", "/unit/level_up", {"unit_id": 1})


func _on_friend_list_button_pressed() -> void:
	await _call_api("POST", "/friend/list")


func _on_friend_apply_list_button_pressed() -> void:
	await _call_api("POST", "/friend/apply/list")


func _on_mailbox_list_button_pressed() -> void:
	await _call_api("POST", "/mailbox/list")


## バージョン確認（サーバーの実装は GET。deploy_version は 0 = 未取得として問い合わせる）
func _on_version_check_button_pressed() -> void:
	await _call_api("GET", "/auth/version?deploy_version=0", {}, {"auth": false})


## login（冪等キー付き。login と同じ操作の確認用）
func _on_login_button_pressed() -> void:
	await _call_api("POST", "/auth/login", {}, {"idempotency_key": IdempotencyKey.generate()})


# クリアボタン
func _on_clear_button_pressed():
	response_text.text = ""
	_append_response("クリアしました")
	_update_status("準備完了", false)


## 戻る（タイトルへ）
func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file(SceneRouter.TITLE_SCENE)


## API を 1 回呼んで、結果をそのまま画面に出す。
func _call_api(
	method: String, endpoint: String, body: Dictionary = {}, options: Dictionary = {}
) -> void:
	_update_status("%s %s ..." % [method, endpoint], false)
	_append_response("\n[リクエスト] %s %s" % [method, endpoint])
	if not body.is_empty():
		_append_response("パラメータ: " + JSON.stringify(body))
	var result: ApiResult = await AppContext.api_client().request(method, endpoint, body, options)
	if result.ok:
		_update_status("成功", false)
		_append_response("[レスポンス] 成功")
		_append_response(JSON.stringify(result.data, "  "))
	else:
		_report_error(result.to_app_error())


## 失敗を画面に出す（種別・コード・共通の文言）。
func _report_error(error: AppError) -> void:
	var text := ErrorMessages.text(error)
	_update_status("エラー: " + text, true)
	_append_response("[エラー] kind=%d code=%d %s" % [error.kind, error.error_code, text])


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
