## 受け取りボタン（VIP の再受け取り）の表示用の値。
##
## visible が真のときだけボタンを出す（VIP の段の can_re_receive が真）。押せない状態の印は出さない（H4）。
## mst_vip_login_bonus_id は POST /login_bonus/receive の本文にそのまま送る値。
class_name ReceiveOffer
extends RefCounted

var visible: bool = false
var mst_vip_login_bonus_id: String = ""


func _init(p_visible: bool = false, p_mst_vip_login_bonus_id: String = "") -> void:
	visible = p_visible
	mst_vip_login_bonus_id = p_mst_vip_login_bonus_id
