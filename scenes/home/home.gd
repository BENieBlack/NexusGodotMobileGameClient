extends Control

# ホーム画面

@onready var welcome_label: Label = $CenterContainer/PanelContainer/VBoxContainer/WelcomeLabel
@onready var user_info_label: Label = $CenterContainer/PanelContainer/VBoxContainer/InfoBg/UserInfoLabel
@onready var api_test_button: Button = $CenterContainer/PanelContainer/VBoxContainer/ApiTestButton

func _ready():
	print("ホーム画面を表示")
	welcome_label.text = "ホーム"

	# ユーザー情報を表示
	if UserDataManager.is_logged_in:
		var user_id = UserDataManager.user_id
		user_info_label.text = "プレイヤーID: " + str(user_id)
	else:
		user_info_label.text = "ログインしていません"

	# ボタンのシグナル接続
	api_test_button.pressed.connect(_on_api_test_button_pressed)

func _on_api_test_button_pressed():
	print("APIテスト画面へ遷移")
	SceneManager.change_scene("res://scenes/api_test/api_test.tscn")
