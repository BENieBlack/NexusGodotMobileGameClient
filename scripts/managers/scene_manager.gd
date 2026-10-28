extends Node

# シーン遷移マネージャー

const TITLE_SCENE = "res://scenes/title/title.tscn"
const AGREEMENT_SCENE = "res://scenes/agreement/agreement.tscn"
const LOGIN_BONUS_SCENE = "res://scenes/login_bonus/login_bonus.tscn"
const HOME_SCENE = "res://scenes/home/home.tscn"

var current_scene: Node = null

func _ready():
	var root = get_tree().root
	current_scene = root.get_child(root.get_child_count() - 1)

# シーンを変更
func change_scene(scene_path: String) -> void:
	print("シーンを変更: ", scene_path)
	call_deferred("_deferred_change_scene", scene_path)

func _deferred_change_scene(scene_path: String) -> void:
	if current_scene:
		current_scene.free()
	
	var new_scene = load(scene_path)
	if new_scene:
		current_scene = new_scene.instantiate()
		get_tree().root.add_child(current_scene)
		get_tree().current_scene = current_scene
	else:
		print("シーンのロードに失敗: ", scene_path)

# タイトル画面へ
func goto_title() -> void:
	change_scene(TITLE_SCENE)

# 利用規約同意画面へ
func goto_agreement() -> void:
	change_scene(AGREEMENT_SCENE)

# ログインボーナス画面へ
func goto_login_bonus() -> void:
	change_scene(LOGIN_BONUS_SCENE)

# ホーム画面へ
func goto_home() -> void:
	change_scene(HOME_SCENE)
