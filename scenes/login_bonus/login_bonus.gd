extends Control

# ログインボーナス画面 - サーバから取得したログインボーナスを表示してタップでホーム画面へ遷移

@onready var bonus_label: Label = $CenterContainer/PanelContainer/VBoxContainer/BonusBg/BonusLabel
@onready var tap_label: Label = $CenterContainer/PanelContainer/VBoxContainer/TapBg/TapLabel

func _ready():
	print("ログインボーナス画面を表示")
	tap_label.text = "タップして続ける"

	# UserDataManagerのlogin_bonus_listを表示
	_display_login_bonus()

# ログインボーナス内容を表示
func _display_login_bonus() -> void:
	var bonus_list: Array = UserDataManager.login_bonus_list

	if bonus_list.is_empty():
		# ログインボーナスなし（本日分取得済み、またはデータ未取得）
		bonus_label.text = "本日のログインボーナス\nは受け取り済みです"
		return

	# ボーナス内容を文字列に組み立てる
	var lines: Array[String] = ["ログインボーナス!"]
	for resource in bonus_list:
		var type_str = _get_resource_type_label(resource.get("type", ""))
		var amount = resource.get("amount", 0)
		var id = resource.get("id", "")
		var metadata = resource.get("metadata", null)

		var item_label = _build_item_label(type_str, id, amount, metadata)
		lines.append(item_label)

	bonus_label.text = "\n".join(lines)
	print("ログインボーナス表示: ", bonus_list.size(), "件")

# リソースタイプを表示用文字列に変換
func _get_resource_type_label(type: String) -> String:
	match type:
		"diamond":
			return "ダイヤ"
		"gold":
			return "ゴールド"
		"stamina":
			return "スタミナ"
		"unit":
			return "ユニット"
		"equipment":
			return "装備"
		"item":
			return "アイテム"
		_:
			return type

# アイテム表示文字列を生成
func _build_item_label(type_label: String, id: String, amount: int, metadata) -> String:
	if metadata != null and metadata is Dictionary:
		# ユニット等はメタデータにgrade/levelが入る
		var grade = metadata.get("grade", 1)
		return "  %s (ID:%s) グレード%d x%d" % [type_label, id, grade, amount]
	else:
		return "  %s (ID:%s) x%d" % [type_label, id, amount]

# 画面タップ検出
func _input(event):
	if event is InputEventScreenTouch and event.pressed:
		_on_screen_tapped()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_screen_tapped()

# 画面がタップされた時
func _on_screen_tapped() -> void:
	print("ログインボーナス画面がタップされました - ホーム画面へ遷移")
	SceneManager.goto_home()
