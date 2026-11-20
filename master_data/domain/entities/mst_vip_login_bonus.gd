## VIP ログインボーナスの本体（mst_vip_login_bonus）と報酬行の読み取りモデル。
##
## 項目: id・vip_level（対象の VIP レベル）・loop_days（周期の日数）・contents（報酬行。day・sort_desc 降順・
##       id 昇順）。本体にも deploy_key は無い（通常の本体と違う）。
class_name MstVipLoginBonus
extends RefCounted

var id: String = ""
var vip_level: int = 0
var loop_days: int = 0
var contents: Array[MstVipLoginBonusContent] = []
