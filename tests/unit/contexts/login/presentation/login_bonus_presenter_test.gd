## LoginBonusPresenter（ログインボーナス画面）の表示とタップのテスト（client_design.md 1-2）。
##
## 受取の有無で文言が変わること、grade は metadata にあるときだけ出ること（課金ボーナスで
## 「グレード1」と誤表示しない。0 節 l）、タップでホームへ 1 回だけ進むことを確かめる。
extends GdUnitTestSuite

const BONUS_SCENE := "res://contexts/login/presentation/login_bonus/login_bonus.tscn"
const BONUS_LABEL_PATH := "CenterContainer/PanelContainer/VBoxContainer/BonusBg/BonusLabel"

var _router: ScreenTestDoubles.FakeRouter
var _repository: LocalLoginBonusRepository


func before_test() -> void:
	_router = ScreenTestDoubles.FakeRouter.new()
	_repository = LocalLoginBonusRepository.new()


func _show_screen() -> Control:
	var screen: LoginBonusPresenter = load(BONUS_SCENE).instantiate()
	screen.setup(GetLoginBonusesUseCase.new(_repository), _router)
	add_child(auto_free(screen))
	await get_tree().process_frame
	return screen


func _tap(screen: Control) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	screen._input(event)


## 前提: 受取が空。期待: 「受け取り済みです」の文言（画面は通信しない）。
func test_empty_shows_already_received() -> void:
	var screen := await _show_screen()
	assert_str((screen.get_node(BONUS_LABEL_PATH) as Label).text).contains("受け取り済みです")


## 前提: 受取が 2 件（グレード付き / 無し）。期待: 種別・ID・数量が出て、グレードは付いている行だけ。
func test_bonuses_show_items_and_grade_only_when_present() -> void:
	var bonuses: Array[LoginBonus] = [
		LoginBonus.new("u1", "gold", "gold", 100, "", {"is_paid": true}),
		LoginBonus.new("u2", "unit", "7", 1, "", {"grade": 3}),
	]
	_repository.replace(bonuses)
	var screen := await _show_screen()
	var text := (screen.get_node(BONUS_LABEL_PATH) as Label).text
	assert_str(text).contains("ゴールド (ID:gold) x100")
	assert_str(text).contains("ユニット (ID:7) グレード3 x1")
	assert_str(text).not_contains("グレード1")


## 前提: 表示中。操作: 画面を 2 回タップ。期待: ホームへの遷移は 1 回だけ。
func test_tap_goes_home_once() -> void:
	var screen := await _show_screen()
	_tap(screen)
	_tap(screen)
	assert_array(_router.calls).contains_exactly(["home"])
