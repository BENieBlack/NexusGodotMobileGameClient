## カレンダーの 1 日分（マスターから作る。client_design.md 2-1）。
##
## day は 1 始まり。rewards はその日の報酬（sort_desc の降順。大きい値が先）。
## 報酬が無い日は空配列（画面は unknown の絵のみ・数量なしで出す）。
## 報酬は login_bonus_list の要素と同じ LoginBonus を使い回す（type = content_type・id = content_mst_id・
## amount = content_quantity × amount・metadata = content_option ＋ 通常の行の is_paid 真なら is_paid: true）。
class_name LoginBonusCalendarDay
extends RefCounted

var day: int = 0
var rewards: Array[LoginBonus] = []


func _init(p_day: int = 0, p_rewards: Array[LoginBonus] = []) -> void:
	day = p_day
	rewards = p_rewards
