## 通常・VIP の 2 段のキーを持つ辞書 → LoginBonusCalendars（list 応答と login 応答の新キーで共用。4 節）。
##
## キー: login_bonus_calendar（通常）・vip_login_bonus_calendar（VIP）。キー欠落・null・Dictionary でないものは、
## その段なし（null）。旧サーバー（新キー無し）の応答は両方 null の束になる。
## 段 1 つの変換は LoginBonusCalendarResponse に任せる（2 通りの変換を作らない）。
class_name LoginBonusCalendarsResponse
extends RefCounted

const NORMAL_KEY := "login_bonus_calendar"
const VIP_KEY := "vip_login_bonus_calendar"


static func from_dict(data: Dictionary) -> LoginBonusCalendars:
	return LoginBonusCalendars.new(
		LoginBonusCalendarResponse.from_variant(data.get(NORMAL_KEY, null), false),
		LoginBonusCalendarResponse.from_variant(data.get(VIP_KEY, null), true)
	)
