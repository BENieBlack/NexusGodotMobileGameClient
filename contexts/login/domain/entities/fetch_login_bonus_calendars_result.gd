## POST /login_bonus/list の結果（Repository の fetch_calendars と UseCase が使う）。
##
## 成功なら calendars（通常・VIP の進捗。段の無い側は null）を持つ。失敗は error（AppError）。
## list 応答の is_granted_now は常に偽（サーバー仕様）なので、再生するスタンプは無い。
class_name FetchLoginBonusCalendarsResult
extends Result

var calendars: LoginBonusCalendars = LoginBonusCalendars.new()


func _init(p_error: AppError = null, p_calendars: LoginBonusCalendars = null) -> void:
	super(p_error == null, p_error)
	if p_calendars != null:
		calendars = p_calendars
