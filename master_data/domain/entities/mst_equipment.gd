## 装備マスター（mst_equipment）の読み取りモデル。
##
## 計算・判定は持たない。type / element / rarity は DB の文字列のまま。
class_name MstEquipment
extends RefCounted

var id: String = ""
var deploy_key: int = 0
var type: String = ""
var element: String = ""
var rarity: String = ""
var attack: int = 0
var defense: int = 0
var hp: int = 0
var sort_desc: int = 0
var is_active: bool = true
