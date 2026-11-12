## ホーム画面の presenter（client_design.md 1-2）。
##
## 目的: ホームにプレイヤー ID を表示する。ホームの中身は今回の機能の対象外（メインメニューは別機能）。
## 表示: プレイヤー ID があれば「プレイヤーID: <id>」、無ければ「ログインしていません」。
## 依存: GetPlayerIdUseCase だけ（テストは setup で偽物を渡す）。
class_name HomePresenter
extends Control

var _get_player_id: GetPlayerIdUseCase
var _is_configured: bool = false

@onready var _welcome_label: Label = $CenterContainer/PanelContainer/VBoxContainer/WelcomeLabel
@onready
var _user_info_label: Label = $CenterContainer/PanelContainer/VBoxContainer/InfoBg/UserInfoLabel


## UseCase を渡す。_ready より前に呼ぶとその値を使い、呼ばなければ _ready がオートロードから取る。
func setup(get_player_id: GetPlayerIdUseCase) -> void:
	_get_player_id = get_player_id
	_is_configured = true


func _ready() -> void:
	if not _is_configured:
		setup(AppContext.get_player_id_use_case())
	_welcome_label.text = "ホーム"
	var player_id := _get_player_id.handle()
	if player_id != "":
		_user_info_label.text = "プレイヤーID: " + player_id
	else:
		_user_info_label.text = "ログインしていません"
