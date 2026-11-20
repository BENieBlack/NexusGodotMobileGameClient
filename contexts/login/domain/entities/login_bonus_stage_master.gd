## 段 1 つのマスター（周期の日数と全日の報酬。client_design.md 2-1）。
##
## cycle_days は mst の loop_days。days は 1..cycle_days の各日（報酬が無い日も空の日として入る）。
## cycle_days が 1 未満・MAX_CYCLE_DAYS 超のときは days を作らない（画面全体を文字の画面に落とす対象。1-3 ③）。
class_name LoginBonusStageMaster
extends RefCounted

## カレンダーに出せる周期の日数の上限（C1。これを超えると文字の画面に落とす）
const MAX_CYCLE_DAYS := 8

var cycle_days: int = 0
var days: Array[LoginBonusCalendarDay] = []


func _init(p_cycle_days: int = 0, p_days: Array[LoginBonusCalendarDay] = []) -> void:
	cycle_days = p_cycle_days
	days = p_days


## 周期の日数がカレンダーに出せる範囲（1〜MAX_CYCLE_DAYS）か。
func is_displayable() -> bool:
	return cycle_days >= 1 and cycle_days <= MAX_CYCLE_DAYS


## day（1 始まり）の日。範囲外は null。
func day_of(day: int) -> LoginBonusCalendarDay:
	if day < 1 or day > days.size():
		return null
	return days[day - 1]
