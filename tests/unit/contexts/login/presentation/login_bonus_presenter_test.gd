## LoginBonusPresenter（ログインボーナス画面）の表示とタップのテスト（client_design.md 1-2）。
##
## 受取の有無で文言が変わること、grade は metadata にあるときだけ出ること（課金ボーナスで
## 「グレード1」と誤表示しない。0 節 l）、タップでホームへ 1 回だけ進むことを確かめる。
extends GdUnitTestSuite


## 偽の MstItemRepository。names にある ID だけ MstItem（名前つき）を返し、無い ID は null。
class FakeMstItemRepository:
	extends MstItemRepository
	var names: Dictionary = {}

	func get_by_id(id: String) -> MstItem:
		if not names.has(id):
			return null
		var item := MstItem.new()
		item.id = id
		item.name = str(names[id])
		return item


const BONUS_SCENE := "res://contexts/login/presentation/login_bonus/login_bonus.tscn"
const BONUS_LABEL_PATH := "CenterContainer/PanelContainer/VBoxContainer/BonusBg/BonusLabel"

var _router: ScreenTestDoubles.FakeRouter
var _repository: LocalLoginBonusRepository
var _items: FakeMstItemRepository


func before_test() -> void:
	_router = ScreenTestDoubles.FakeRouter.new()
	_repository = LocalLoginBonusRepository.new()
	_items = FakeMstItemRepository.new()


func _show_screen() -> Control:
	var screen: LoginBonusPresenter = load(BONUS_SCENE).instantiate()
	screen.setup(
		GetLoginBonusDisplaysUseCase.new(GetLoginBonusesUseCase.new(_repository), _items), _router
	)
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


func _text_with(bonuses: Array[LoginBonus]) -> String:
	_repository.replace(bonuses)
	var screen := await _show_screen()
	return (screen.get_node(BONUS_LABEL_PATH) as Label).text


## 前提: free_diamond の名前がマスターで引ける。期待: 「<名前> x100」（ID は出さない）。
func test_free_diamond_uses_master_name() -> void:
	_items.names = {"free_diamond": "無償ダイヤ（確認用）"}
	var text := await _text_with([LoginBonus.new("u", "item", "free_diamond", 100)])
	assert_str(text).contains("無償ダイヤ（確認用） x100")
	assert_str(text).not_contains("ID:")


## 前提: free_diamond の名前が引けない（null）・name が空。期待: どちらも「無償ダイヤ x100」。
func test_free_diamond_falls_back_to_fixed_name() -> void:
	var text := await _text_with([LoginBonus.new("u", "item", "free_diamond", 100)])
	assert_str(text).contains("無償ダイヤ x100")
	assert_str(text).not_contains("ID:")
	_items.names = {"free_diamond": ""}
	var text2 := await _text_with([LoginBonus.new("u", "item", "free_diamond", 100)])
	assert_str(text2).contains("無償ダイヤ x100")


## 前提: 他の item。期待: 名前が引ければ「<名前> x3」、引けなければ従来の「アイテム (ID:…) x3」。
func test_other_item_name_or_legacy_label() -> void:
	_items.names = {"stamina_50": "スタミナ回復"}
	var text := await _text_with([LoginBonus.new("u", "item", "stamina_50", 3)])
	assert_str(text).contains("スタミナ回復 x3")
	var text2 := await _text_with([LoginBonus.new("u", "item", "other", 3)])
	assert_str(text2).contains("アイテム (ID:other) x3")


## 前提: 旧種別 diamond。期待: 特別扱いせず種別をそのまま出す（互換なし）。
func test_legacy_diamond_type_is_shown_as_unknown() -> void:
	var text := await _text_with([LoginBonus.new("u", "diamond", "diamond", 20)])
	assert_str(text).contains("diamond (ID:diamond) x20")
