## version API の master.tables の 1 テーブル分（MasterVersion.tables の要素）。
##
## 目的: 生の Dictionary（{hash, url, file_size}）を domain に渡さず、項目を型で持つ
##       （architecture.md 2 節「API 応答」: domain に生の Dictionary を渡さない）。
## 項目: name（テーブル名。例: mst_unit）、hash（このテーブルのファイルのハッシュ）、
##       url（配信ファイルの場所。相対パスか絶対 URL。解決は data の API Repository）、file_size（バイト）
class_name MasterTable
extends RefCounted

var name: String = ""
var hash: String = ""
var url: String = ""
var file_size: int = 0


func _init(
	p_name: String = "", p_hash: String = "", p_url: String = "", p_file_size: int = 0
) -> void:
	name = p_name
	hash = p_hash
	url = p_url
	file_size = p_file_size
