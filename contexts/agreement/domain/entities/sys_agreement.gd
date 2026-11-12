## 未同意の規約 1 件の読み取りモデル（サーバー api.md 7 節 agreement_list の要素）。
##
## 目的: 規約画面がカードを表示し、同意（sys_agreement_id）を送るための値。計算・判定は持たない。
## 項目: sys_agreement_id / version / title / url（規約本文の URL）/ published_at（"Y-m-d H:i:s"。解釈しない）
class_name SysAgreement
extends RefCounted

var sys_agreement_id: int = 0
var version: String = ""
var title: String = ""
var url: String = ""
var published_at: String = ""


func _init(
	p_sys_agreement_id: int = 0,
	p_version: String = "",
	p_title: String = "",
	p_url: String = "",
	p_published_at: String = ""
) -> void:
	sys_agreement_id = p_sys_agreement_id
	version = p_version
	title = p_title
	url = p_url
	published_at = p_published_at
