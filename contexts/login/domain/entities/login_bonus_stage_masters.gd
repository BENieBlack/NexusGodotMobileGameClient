## 通常・VIP の 2 段のマスターの束（PrepareLoginBonusMasterUseCase の結果の中身）。
##
## normal・vip は、引けた段だけ非 null（段の進捗が無い・マスターを引けないときは null）。
## normal_status・vip_status は引きの結果の種別（ログイン・テスト用。進捗の無い段は NOT_FOUND ではなく「引いていない」
## ので、has_normal_lookup・has_vip_lookup で区別する）。
class_name LoginBonusStageMasters
extends RefCounted

var normal: LoginBonusStageMaster = null
var vip: LoginBonusStageMaster = null
var normal_status: MstLookupStatus.Status = MstLookupStatus.Status.UNREADABLE
var vip_status: MstLookupStatus.Status = MstLookupStatus.Status.UNREADABLE
## その段のマスターを実際に引いたか（進捗の段があったときだけ引く）
var has_normal_lookup: bool = false
var has_vip_lookup: bool = false


## calendars の「あるべき段」のマスターが全部引けているか。段の進捗が無い側は問わない。
## 偽なら、古いマスターとして再取得の対象にする（2-4）。
func covers(calendars: LoginBonusCalendars) -> bool:
	if calendars.normal != null and normal == null:
		return false
	if calendars.vip != null and vip == null:
		return false
	return true
