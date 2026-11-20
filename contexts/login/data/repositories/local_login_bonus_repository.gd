## ログインボーナスの保持先（LoginBonusRepository の実装。メモリのみ）。
##
## 目的: login の受取結果を、ログインボーナス画面が表示するまで持つ（画面は通信しない）。
##       永続化しない。セッションが無効になったとき（EventBus.session_expired。AppContext が受け手として登録）に
##       clear() で空にする（受取結果と、カレンダーの段の進捗 LoginBonusCalendars の両方）。
class_name LocalLoginBonusRepository
extends LoginBonusRepository

var _bonuses: Array[LoginBonus] = []
var _calendars: LoginBonusCalendars = LoginBonusCalendars.new()


func replace(bonuses: Array[LoginBonus]) -> void:
	_bonuses = bonuses


func list() -> Array[LoginBonus]:
	return _bonuses


func replace_calendars(calendars: LoginBonusCalendars) -> void:
	_calendars = calendars if calendars != null else LoginBonusCalendars.new()


func calendars() -> LoginBonusCalendars:
	return _calendars


func clear() -> void:
	_bonuses = []
	_calendars = LoginBonusCalendars.new()
