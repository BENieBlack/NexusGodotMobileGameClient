## ログインボーナスの保持先（LoginBonusRepository の実装。メモリのみ）。
##
## 目的: login の受取結果を、ログインボーナス画面が表示するまで持つ（画面は通信しない）。
##       永続化しない。セッションが無効になったとき（EventBus.session_expired。AppContext が受け手として登録）に
##       clear() で空にする。
class_name LocalLoginBonusRepository
extends LoginBonusRepository

var _bonuses: Array[LoginBonus] = []


func replace(bonuses: Array[LoginBonus]) -> void:
	_bonuses = bonuses


func list() -> Array[LoginBonus]:
	return _bonuses


func clear() -> void:
	_bonuses = []
