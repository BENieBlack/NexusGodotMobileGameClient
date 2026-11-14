## スタミナの表示値（client_design.md 2-2）。StaminaRecovery の計算結果で、保持しない。
class_name StaminaDisplay
extends RefCounted

## 表示する現在値
var current: int = 0
## 最大値。-1 は不明（「42 / --」と出す）
var max_stamina: int = -1
## 次の 1 点までの秒。-1 は出さない（最大値・計算不能・行なし）
var seconds_to_next: int = -1
## スタミナの行があるか（無ければ「-」）
var is_present: bool = false


func _init(
	p_current: int = 0,
	p_max_stamina: int = -1,
	p_seconds_to_next: int = -1,
	p_is_present: bool = false
) -> void:
	current = p_current
	max_stamina = p_max_stamina
	seconds_to_next = p_seconds_to_next
	is_present = p_is_present
