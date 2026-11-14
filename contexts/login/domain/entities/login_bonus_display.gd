## ログインボーナス 1 件の表示用の値（client_design.md 3-3）。
##
## 目的: 受取内容（LoginBonus）と、マスターから引いたアイテム名を 1 組にして presenter へ渡す。
## 項目:
##   bonus      受取内容そのもの
##   item_name  type が item で名前が引けたときだけ入る。それ以外（他の種別・引けない・空）は空文字
## 名前が空のときの代替の文字は presenter が LoginBonus の定数から決める（ここは値だけ持つ）。
class_name LoginBonusDisplay
extends RefCounted

var bonus: LoginBonus
var item_name: String = ""


func _init(p_bonus: LoginBonus = null, p_item_name: String = "") -> void:
	bonus = p_bonus
	item_name = p_item_name
