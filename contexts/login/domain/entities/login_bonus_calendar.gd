## カレンダー 1 段（通常または VIP）の**進捗**（応答の値だけ。client_design.md 2-1・4 節）。
##
## 目的: login 応答・list 応答・receive 応答の段 1 つ分を、画面が使う短い名前で持つ。
##       日ごとの報酬・周期の日数は応答に無く、マスターから引く（LoginBonusStageMaster）。
## 項目（応答の名前との対応は 4 節の表の 1 か所だけ。変換は data/api の LoginBonusCalendarResponse）:
##   mst_id            応答の mst_login_bonus_id（通常）／mst_vip_login_bonus_id（VIP）。無ければ空文字
##   last_day          応答の last_received_day。null（まだ配っていない）は 0
##   is_granted_today  今日の分は配布済みか（今日の段の根拠）
##   is_granted_now    この応答でスタンプのアニメーションを再生する段か（T5）
##   can_re_receive    再受け取りが可能か（VIP のみ。ボタンを出す根拠）
##   vip_level         VIP の対象レベル（VIP のみ。無ければ 0）
## 判定は足さない（今日の段かどうかなどは GetLoginBonusScreenUseCase が決める）。
class_name LoginBonusCalendar
extends RefCounted

var mst_id: String = ""
var last_day: int = 0
var is_granted_today: bool = false
var is_granted_now: bool = false
var can_re_receive: bool = false
var vip_level: int = 0


func _init(
	p_mst_id: String = "",
	p_last_day: int = 0,
	p_is_granted_today: bool = false,
	p_is_granted_now: bool = false,
	p_can_re_receive: bool = false,
	p_vip_level: int = 0
) -> void:
	mst_id = p_mst_id
	last_day = p_last_day
	is_granted_today = p_is_granted_today
	is_granted_now = p_is_granted_now
	can_re_receive = p_can_re_receive
	vip_level = p_vip_level


## 再受け取りのあとの状態の複製（is_granted_now = true・can_re_receive = false）。元は変えない。
## 応答の段が読めなかったときの代替に使う（サーバーの値を正とするのが原則）。
func duplicate_as_re_received() -> LoginBonusCalendar:
	return LoginBonusCalendar.new(mst_id, last_day, is_granted_today, true, false, vip_level)
