class_name SysAgreement
extends RefCounted

# 利用規約モデル

var sys_agreement_id: int = 0
var version: String = ""
var title: String = ""
var url: String = ""
var published_at: String = ""

# レスポンスのDictionaryからインスタンスを生成
static func from_dict(data: Dictionary) -> SysAgreement:
	var agreement = SysAgreement.new()

	if data.has("sys_agreement_id"):
		agreement.sys_agreement_id = int(data["sys_agreement_id"])
	if data.has("version"):
		agreement.version = str(data["version"])
	if data.has("title"):
		agreement.title = str(data["title"])
	if data.has("url"):
		agreement.url = str(data["url"])
	if data.has("published_at"):
		agreement.published_at = str(data["published_at"])

	return agreement

# デバッグ用の文字列表現
func _to_string() -> String:
	return "SysAgreement(id=%d, title=%s, version=%s)" % [sys_agreement_id, title, version]
