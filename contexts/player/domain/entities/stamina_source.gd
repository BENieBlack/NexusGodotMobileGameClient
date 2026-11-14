## スタミナ回復の計算の起点（client_design.md 2-2・3-1）。不変の値。
##
## login 応答の current_stamina と last_recovery_at を「起点」として一度だけ持ち、表示のたびに
## この起点から now までを計算する。計算結果をここへ書き戻さない（二重加算を防ぐ）ので、
## 生成後は変更しない前提（フィールドは読むだけ）。
## 読めなかった値は番兵で表す: recovered_at_unix = -1、rate_x100 = 0、max_stamina = -1、interval_seconds = 0。
class_name StaminaSource
extends RefCounted

## login 時点の現在値
var current: int = 0
## last_recovery_at の UNIX 秒（UTC）。読めなければ -1
var recovered_at_unix: int = -1
## recovery_rate_multiplier を 100 倍した整数（"1.50" → 150）。読めなければ 0
var rate_x100: int = 0
## 最大スタミナ（mst_player_level）。分からなければ -1
var max_stamina: int = -1
## 回復間隔の秒（mst_config）。分からなければ 0
var interval_seconds: int = 0
## type が normal の行があったか（無ければ「-」表示）
var is_present: bool = false


func _init(
	p_current: int = 0,
	p_recovered_at_unix: int = -1,
	p_rate_x100: int = 0,
	p_max_stamina: int = -1,
	p_interval_seconds: int = 0,
	p_is_present: bool = false
) -> void:
	current = p_current
	recovered_at_unix = p_recovered_at_unix
	rate_x100 = p_rate_x100
	max_stamina = p_max_stamina
	interval_seconds = p_interval_seconds
	is_present = p_is_present
