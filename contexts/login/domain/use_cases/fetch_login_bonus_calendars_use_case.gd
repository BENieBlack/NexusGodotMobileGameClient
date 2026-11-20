## 段の進捗を取り直す UseCase（POST /login_bonus/list。client_design.md 3-1・3-2）。
##
## 目的: ホームから開いた画面（FROM_HOME）の最初の取得と、再受け取りが業務エラー（26001〜26003）に
##       なったあとの取り直し。login 応答は古くなりうるので、画面を開くたびに呼ぶ。
## 流れ（handle）:
##   1. LoginBonusCalendarRepository.fetch_calendars()（冪等キーは付けない。list は再試行でも付けない）
##   2. 成功したら、メモリの保持を置き換える（通常・VIP の両方。応答に無い段は null になる）
##   3. 失敗は何も反映せずその結果（error）を返す
## 注意: list 応答の is_granted_now は常に偽なので、取り直した画面はスタンプを再生しない。
class_name FetchLoginBonusCalendarsUseCase
extends RefCounted

var _calendar_repository: LoginBonusCalendarRepository
var _login_bonus_repository: LoginBonusRepository


func _init(
	calendar_repository: LoginBonusCalendarRepository, login_bonus_repository: LoginBonusRepository
) -> void:
	_calendar_repository = calendar_repository
	_login_bonus_repository = login_bonus_repository


func handle() -> FetchLoginBonusCalendarsResult:
	var result := await _calendar_repository.fetch_calendars()
	if not result.ok:
		return result
	_login_bonus_repository.replace_calendars(result.calendars)
	return result
