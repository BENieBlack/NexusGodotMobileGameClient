## 直近の login で受け取ったログインボーナスの一覧を返す UseCase。
##
## 目的: ログインボーナス画面が表示内容を受け取る窓口（画面は通信しない。client_design.md 1-1）。
##       presenter が Repository を直接触らない。
## 戻り値: 受取内容の一覧。空なら本日分は受け取り済み（または未取得）。
class_name GetLoginBonusesUseCase
extends RefCounted

var _login_bonus_repository: LoginBonusRepository


func _init(login_bonus_repository: LoginBonusRepository) -> void:
	_login_bonus_repository = login_bonus_repository


## ログインボーナスの一覧を返す。
func handle() -> Array[LoginBonus]:
	return _login_bonus_repository.list()
