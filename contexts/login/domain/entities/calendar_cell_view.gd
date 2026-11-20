## カレンダーの 1 マス（1 日分）の表示用の値。presenter が描くだけの値で、文字列は持たない。
##
## 状態（state。1-3 のマスの状態）:
##   TODAY    今日（色付きの縁取りと「今日」の印）。play_stamp が真ならスタンプのアニメーション、偽なら押印済み
##   RECEIVED 今日より前（少し暗く、押印済み）
##   FUTURE   未来（彩度・明るさを落とす）
##   NEUTRAL  今日の段でない段・日数が範囲外の段（全マスを同じ見た目。強調もスタンプも無し）
## 絵の引数（ItemIcon.setup に渡す値）: icon_type・icon_id・icon_mst_item_type。先頭の報酬から決める。
##   報酬が無い日は空文字（ItemIconResolver が unknown の絵にする）。
## 報酬: rewards は sort_desc 降順（大きい値が先）。先頭が絵と数量になり、extra_count（件数 − 1）が「＋n」。
## 報酬が無い日は is_empty が真（unknown の絵のみ・数量なし）。
class_name CalendarCellView
extends RefCounted

enum State { TODAY, RECEIVED, FUTURE, NEUTRAL }

var day: int = 0
var state: State = State.NEUTRAL
var play_stamp: bool = false
var rewards: Array[LoginBonusDisplay] = []
var extra_count: int = 0
var icon_type: String = ""
var icon_id: String = ""
var icon_mst_item_type: String = ""
## 先頭の報酬の数量（content_quantity × amount）。報酬が無い日は 0
var quantity: int = 0
var is_empty: bool = true
