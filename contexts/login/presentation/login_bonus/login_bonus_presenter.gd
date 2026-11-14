## ログインボーナス画面の presenter（client_design.md 1-2）。
##
## 目的: 直近の login で受け取ったログインボーナスを表示し、タップでホームへ進む。
##       この画面は通信しない（login は成功済みでここへ来る。表示内容は UseCase 経由で受け取る）。
## 表示:
##   - 受取あり → 種別・ID・数量（metadata に grade があるときだけ「グレード N」を添える。設計 0 節 l）
##     type が item の行は mst_item の名前（l10n）を優先する。引けないときは無償ダイヤなら「無償ダイヤ」、
##     他のアイテムは従来の「アイテム (ID:…)」（free-diamond-item client_design.md 3-2）
##   - 受取なし（空）→「本日のログインボーナスは受け取り済みです」
## 遷移: 画面のタップ（マウス・タッチ）でホームへ。連打で二重に遷移しない。
## 依存: GetLoginBonusDisplaysUseCase だけ。遷移は既定ではオートロードの SceneRouter（テストは setup で偽物を渡す）。
class_name LoginBonusPresenter
extends Control

var _get_login_bonus_displays: GetLoginBonusDisplaysUseCase
var _router: Object
var _is_configured: bool = false
var _is_leaving: bool = false

@onready var _bonus_label: Label = $CenterContainer/PanelContainer/VBoxContainer/BonusBg/BonusLabel
@onready var _tap_label: Label = $CenterContainer/PanelContainer/VBoxContainer/TapBg/TapLabel


## UseCase と遷移の相手を渡す。_ready より前に呼ぶとその値を使い、呼ばなければ _ready がオートロードから取る。
func setup(get_login_bonus_displays: GetLoginBonusDisplaysUseCase, router: Object) -> void:
	_get_login_bonus_displays = get_login_bonus_displays
	_router = router
	_is_configured = true


func _ready() -> void:
	if not _is_configured:
		setup(AppContext.get_login_bonus_displays_use_case(), SceneRouter)
	_tap_label.text = "タップして続ける"
	# 名前の引きは画面を開くとき 1 回だけ（表示中の master_data_loaded は購読しない。設計 3-3）
	_bonus_label.text = build_text(_get_login_bonus_displays.handle())


## 表示する文を組み立てる。受取なしなら受け取り済みの文言。
static func build_text(displays: Array[LoginBonusDisplay]) -> String:
	if displays.is_empty():
		return "本日のログインボーナス\nは受け取り済みです"
	var lines: Array[String] = ["ログインボーナス!"]
	for display in displays:
		lines.append(_build_item_label(display))
	return "\n".join(lines)


## 1 件分の行。metadata に grade があるときだけグレードを添える
## （課金ボーナスの metadata は {"is_paid": true} などで、grade があるとは限らない）。
## 名前が決まる行（マスターの名前・無償ダイヤの固定名）は「名前 x数量」、それ以外は「種別 (ID:…) x数量」。
static func _build_item_label(display: LoginBonusDisplay) -> String:
	var bonus := display.bonus
	var name := _display_name(display)
	# 名前がある行は ID を出さない（ID のままより読みやすいため。設計 3-2）
	var head := name if name != "" else "%s (ID:%s)" % [_resource_type_label(bonus.type), bonus.id]
	if bonus.has_grade():
		return "  %s グレード%d x%d" % [head, int(bonus.metadata["grade"]), bonus.amount]
	return "  %s x%d" % [head, bonus.amount]


## 名前で出せる行の名前を返す。出せない行は空文字（種別と ID の形で出す）。
## 優先: マスターの名前 → 無償ダイヤの固定名（マスターが同梱 DB・名前行なしでも「アイテム (ID:free_diamond)」にしない）。
static func _display_name(display: LoginBonusDisplay) -> String:
	if display.item_name != "":
		return display.item_name
	if display.bonus.is_free_diamond():
		return LoginBonus.FREE_DIAMOND_FALLBACK_NAME
	return ""


## リソースの種別を表示用の文字にする。未知の種別（旧 diamond・paid_diamond を含む）はそのまま出す
## （旧クライアント互換の特別扱いはしない。設計 3-2・P3）。
static func _resource_type_label(type: String) -> String:
	match type:
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


## 画面のタップを検出する（マウスの左ボタン・タッチ）。
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_screen_tapped()
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_screen_tapped()


## 画面がタップされた。ホームへ進む（1 回だけ）。
func _on_screen_tapped() -> void:
	if _is_leaving:
		return
	_is_leaving = true
	_router.goto_home()
