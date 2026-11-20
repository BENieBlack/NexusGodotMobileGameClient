## カレンダー 1 段（通常または VIP）の表示用の値。
##
## 項目: is_vip・vip_level（VIP の見出し「VIP ボーナス　VIP n」の n。n はサーバーが返す対象レベル。0 なら見出しのみ）・
##       cycle_days（マスターの周期の日数。行数の元）・is_today_stage（今日の段か。1-3）・cells（1..cycle_days の順）。
class_name CalendarStageView
extends RefCounted

var is_vip: bool = false
var vip_level: int = 0
var cycle_days: int = 0
var is_today_stage: bool = false
var cells: Array[CalendarCellView] = []
