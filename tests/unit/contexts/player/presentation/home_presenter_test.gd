## HomePresenter（ホーム画面）の表示のテスト（client_design.md 1-2）。プレイヤー ID の表示だけを確かめる。
extends GdUnitTestSuite

const HOME_SCENE := "res://contexts/player/presentation/home/home.tscn"
const INFO_PATH := "CenterContainer/PanelContainer/VBoxContainer/InfoBg/UserInfoLabel"


func _show_home(repository: LocalPlayerRepository) -> Control:
	var screen: HomePresenter = load(HOME_SCENE).instantiate()
	screen.setup(GetPlayerIdUseCase.new(repository))
	add_child(auto_free(screen))
	await get_tree().process_frame
	return screen


## 前提: login 済み（my_id = "abc"）。期待: 「プレイヤーID: abc」を出す。
func test_shows_player_id() -> void:
	var repository := LocalPlayerRepository.new()
	repository.replace(PlayerState.new({"my_id": "abc"}, {}))
	var screen := await _show_home(repository)
	assert_str((screen.get_node(INFO_PATH) as Label).text).is_equal("プレイヤーID: abc")


## 前提: 未ログイン（状態が空）。期待: 「ログインしていません」を出す。
func test_shows_not_logged_in_when_empty() -> void:
	var screen := await _show_home(LocalPlayerRepository.new())
	assert_str((screen.get_node(INFO_PATH) as Label).text).is_equal("ログインしていません")
