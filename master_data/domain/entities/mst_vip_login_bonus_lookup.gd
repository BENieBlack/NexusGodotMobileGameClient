## MstVipLoginBonusRepository.find_by_id の結果（種別と、見つかったときの本体）。
class_name MstVipLoginBonusLookup
extends RefCounted

var status: MstLookupStatus.Status = MstLookupStatus.Status.UNREADABLE
## status が FOUND のときだけ非 null
var bonus: MstVipLoginBonus = null


func _init(
	p_status: MstLookupStatus.Status = MstLookupStatus.Status.UNREADABLE,
	p_bonus: MstVipLoginBonus = null
) -> void:
	status = p_status
	bonus = p_bonus
