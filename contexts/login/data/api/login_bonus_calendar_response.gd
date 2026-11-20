## カレンダー 1 段（通常または VIP）の応答の辞書 → LoginBonusCalendar（腐敗防止層。client_design.md 4 節）。
##
## login 応答・list 応答・receive 応答で共用する（段の形は同じ。2 通りの変換を作らない）。
## 応答の形: { mst_login_bonus_id | mst_vip_login_bonus_id, last_received_day|null, is_granted_today,
##             is_granted_now, [VIP のみ: vip_level, can_re_receive] }。全日の報酬・周期の日数は応答に無い。
## null・欠落・型違いの扱い（D3）:
##   段の辞書が無い・null・Dictionary でない → null（その段を出さない）
##   mst id            文字列。無い・null → 空文字
##   last_received_day null・無い → 0（int() に直す。数値でないものも 0）
##   真偽値 3 つ        真偽値型のときだけその値。それ以外（null・無い・0/1・文字列）は偽（安全側）
##   vip_level         int() に直す。無い・null → 0
##   can_re_receive    VIP のみ読む（通常に付いていても無視）。VIP で段の ID が空のときは偽に落とす（送る ID が無い）
class_name LoginBonusCalendarResponse
extends RefCounted

## 応答の ID の項目名（通常・VIP）
const NORMAL_ID_KEY := "mst_login_bonus_id"
const VIP_ID_KEY := "mst_vip_login_bonus_id"


## 段 1 つの値（辞書でなければ null）を LoginBonusCalendar にする。is_vip は VIP の段か。
static func from_variant(raw: Variant, is_vip: bool) -> LoginBonusCalendar:
	if not (raw is Dictionary):
		if raw != null:
			push_warning("カレンダーの段が辞書でないため、その段なしとして扱います")
		return null
	var data: Dictionary = raw
	var id_key := VIP_ID_KEY if is_vip else NORMAL_ID_KEY
	var mst_id := _string_of(data.get(id_key, null))
	var can_re_receive := false
	var vip_level := 0
	if is_vip:
		vip_level = _int_of(data.get("vip_level", null))
		# 送る ID が無ければボタンを出さない
		can_re_receive = _bool_of(data.get("can_re_receive", null)) and mst_id != ""
	return LoginBonusCalendar.new(
		mst_id,
		_int_of(data.get("last_received_day", null)),
		_bool_of(data.get("is_granted_today", null)),
		_bool_of(data.get("is_granted_now", null)),
		can_re_receive,
		vip_level
	)


static func _string_of(value: Variant) -> String:
	return "" if value == null else str(value)


## JSON の数値は float で来るので int() に直す。数値以外（null・文字列）は 0。
static func _int_of(value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	return 0


## 真偽値型のときだけその値。0/1・文字列・null は偽（安全側。ボタンもアニメーションも出さない）。
static func _bool_of(value: Variant) -> bool:
	return value if value is bool else false
