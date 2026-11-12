## ガチャマスター（mst_gacha）の読み取りモデル。
##
## 計算・判定（開催中か等）は持たない。start_at / end_at は DB の文字列のまま（空なら期限なし）。
## 名前: 旧 MstGacha と衝突するため MasterGacha（master_unit.gd の注記と同じ理由）。
class_name MasterGacha
extends RefCounted

var id: String = ""
var deploy_key: int = 0
var sort_desc: int = 0
var is_active: bool = true
var start_at: String = ""
var end_at: String = ""
var daily_limit: int = 0
var has_step_up: bool = false
