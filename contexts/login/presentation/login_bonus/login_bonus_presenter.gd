## ログインボーナス画面の presenter（client_design.md 1-2）。
##
## 目的: 直近の login で受け取ったログインボーナスを表示し、タップでホームへ進む。
##       この画面は通信しない（login は成功済みでここへ来る。表示内容は UseCase 経由で受け取る）。
## 表示:
##   - 受取あり → 種別・ID・数量（metadata に grade があるときだけ「グレード N」を添える。設計 0 節 l）
##   - 受取なし（空）→「本日のログインボーナスは受け取り済みです」
## 遷移: 画面のタップ（マウス・タッチ）でホームへ。連打で二重に遷移しない。
## 依存: GetLoginBonusesUseCase だけ。遷移は既定ではオートロードの SceneRouter（テストは setup で偽物を渡す）。
class_name LoginBonusPresenter
extends Control

var _get_login_bonuses: GetLoginBonusesUseCase
var _router: Object
var _is_configured: bool = false
var _is_leaving: bool = false

@onready var _bonus_label: Label = $CenterContainer/PanelContainer/VBoxContainer/BonusBg/BonusLabel
@onready var _tap_label: Label = $CenterContainer/PanelContainer/VBoxContainer/TapBg/TapLabel


## UseCase と遷移の相手を渡す。_ready より前に呼ぶとその値を使い、呼ばなければ _ready がオートロードから取る。
func setup(get_login_bonuses: GetLoginBonusesUseCase, router: Object) -> void:
	_get_login_bonuses = get_login_bonuses
	_router = router
	_is_configured = true


func _ready() -> void:
	if not _is_configured:
		setup(AppContext.get_login_bonuses_use_case(), SceneRouter)
	_tap_label.text = "タップして続ける"
	_bonus_label.text = build_text(_get_login_bonuses.handle())


## 表示する文を組み立てる。受取なしなら受け取り済みの文言。
static func build_text(bonuses: Array[LoginBonus]) -> String:
	if bonuses.is_empty():
		return "本日のログインボーナス\nは受け取り済みです"
	var lines: Array[String] = ["ログインボーナス!"]
	for bonus in bonuses:
		lines.append(_build_item_label(bonus))
	return "\n".join(lines)


## 1 件分の行。metadata に grade があるときだけグレードを添える
## （課金ボーナスの metadata は {"is_paid": true} などで、grade があるとは限らない）。
static func _build_item_label(bonus: LoginBonus) -> String:
	var type_label := _resource_type_label(bonus.type)
	if bonus.has_grade():
		return (
			"  %s (ID:%s) グレード%d x%d"
			% [type_label, bonus.id, int(bonus.metadata["grade"]), bonus.amount]
		)
	return "  %s (ID:%s) x%d" % [type_label, bonus.id, bonus.amount]


## リソースの種別を表示用の文字にする。未知の種別はそのまま出す。
static func _resource_type_label(type: String) -> String:
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
