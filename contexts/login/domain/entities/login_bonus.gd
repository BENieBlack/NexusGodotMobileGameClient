## ログインボーナスの受取結果 1 件の読み取りモデル（サーバー api.md 6 節 login_bonus_list の要素）。
##
## 目的: ログインボーナス画面が「何を受け取ったか」を表示するための値。計算・判定は持たない。
## 項目（サーバーの 6 キー。常にすべて出る）:
##   unique_id  配布のたびに作る UUID
##   type       ResourceType の値（item / unit / equipment / stamina、wallet は gold など）。
##              無償ダイヤは type = item・id = free_diamond（種別 diamond は廃止。free-diamond-item）
##   id         content_mst_id
##   amount     数量
##   expire_at  常に null（空文字で表す）。ログインボーナスは期限を設定しない
##   metadata   null 可（辞書で表し、null のときは空の辞書）。is_paid や grade などが入りうる
## null と欠落は同じに扱う（D3）。変換は data/api の LoginResponse が行う。
class_name LoginBonus
extends RefCounted

## type が「アイテム」の値（サーバーの ResourceType::ITEM）
const TYPE_ITEM := "item"
## 無償ダイヤのアイテム ID（サーバーの mst_item.id。player の PlayerResourceIds とは別に持つ二重管理。
## login コンテキストの中で閉じるため、player の定数には依存しない）
const FREE_DIAMOND_ID := "free_diamond"
## 名前が引けないときの無償ダイヤの表示名（人の決定 Q-C1。presenter が使う）
const FREE_DIAMOND_FALLBACK_NAME := "無償ダイヤ"

var unique_id: String = ""
var type: String = ""
var id: String = ""
var amount: int = 0
var expire_at: String = ""
var metadata: Dictionary = {}


func _init(
	p_unique_id: String = "",
	p_type: String = "",
	p_id: String = "",
	p_amount: int = 0,
	p_expire_at: String = "",
	p_metadata: Dictionary = {}
) -> void:
	unique_id = p_unique_id
	type = p_type
	id = p_id
	amount = p_amount
	expire_at = p_expire_at
	metadata = p_metadata


## metadata に grade キーがあるか（表示は「あるときだけ」。client_design.md 0 節 l）。
func has_grade() -> bool:
	return metadata.has("grade")


## 無償ダイヤの受取か（type が item かつ id が free_diamond。id だけでは判定しない）。
## 名前がマスターから引けないときに、固定の「無償ダイヤ」を出すかの判定に使う。
func is_free_diamond() -> bool:
	return type == TYPE_ITEM and id == FREE_DIAMOND_ID
