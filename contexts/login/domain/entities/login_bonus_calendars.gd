## 通常・VIP の 2 段の進捗の束（login 応答・list 応答の 2 キー。client_design.md 2-1）。
##
## normal・vip は、その段が無い（キー欠落・null・型違い）ときに null。段が無い段は画面に出さない（T4）。
class_name LoginBonusCalendars
extends RefCounted

var normal: LoginBonusCalendar = null
var vip: LoginBonusCalendar = null


func _init(p_normal: LoginBonusCalendar = null, p_vip: LoginBonusCalendar = null) -> void:
	normal = p_normal
	vip = p_vip


## どちらかの段があるか。
func has_any() -> bool:
	return normal != null or vip != null
