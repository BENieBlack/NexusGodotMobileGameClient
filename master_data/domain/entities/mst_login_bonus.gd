## 通常のログインボーナスの本体（mst_login_bonus）と報酬行の読み取りモデル。
##
## 目的: 段の ID（応答の mst_login_bonus_id）から引いた、周期の日数と全日の報酬。
## 項目: deploy_key・id・loop_days（周期の日数）・contents（報酬行。day・sort_desc 降順・content_type・
##       content_mst_id の順。並びは SQL が作る）。本体と報酬行は別の SQLite ファイルなので 2 回に分けて引く。
class_name MstLoginBonus
extends RefCounted

var deploy_key: int = 0
var id: String = ""
var loop_days: int = 0
var contents: Array[MstLoginBonusContent] = []
