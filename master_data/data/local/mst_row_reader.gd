## SQLite の 1 行（Dictionary）から値を安全に読む補助（mst Repository の実装が共用する）。
##
## 目的: SQLite の NULL・0/1 の整数・JSON 文字列を、型付きの既定値つきで読む。
##       Repository ごとに同じ変換を書かない。例外にしない（NULL・型違いは既定値）。
class_name MstRowReader
extends RefCounted


## 文字列。NULL・キー無しは空文字。
static func get_string(row: Dictionary, key: String) -> String:
	var value: Variant = row.get(key, null)
	return "" if value == null else str(value)


## 整数。NULL・キー無し・数値でない文字列は 0。
static func get_int(row: Dictionary, key: String) -> int:
	var value: Variant = row.get(key, null)
	if value is int or value is float:
		return int(value)
	if value is String and (value as String).is_valid_int():
		return int(value)
	return 0


## 真偽値。SQLite は 0/1 の整数で返すので、0 以外を真にする。NULL・キー無しは偽。
## 真偽値型・"1"/"true" の文字列も真として読む（配信ファイルの作りの差を吸収する）。
static func get_bool(row: Dictionary, key: String) -> bool:
	var value: Variant = row.get(key, null)
	if value is bool:
		return value
	if value is int or value is float:
		return value != 0
	if value is String:
		return value == "1" or (value as String).to_lower() == "true"
	return false


## JSON 文字列の列を辞書に直す。NULL・空・壊れた JSON・辞書でない JSON は空の辞書（落とさない）。
static func get_json_dict(row: Dictionary, key: String) -> Dictionary:
	var value: Variant = row.get(key, null)
	if value is Dictionary:
		return value
	if not (value is String) or (value as String).strip_edges() == "":
		return {}
	# JSON.new().parse() はエラーをログに出さず、戻り値で成否を返す（壊れた設定を静かに空にする）
	var json := JSON.new()
	if json.parse(value) != OK:
		return {}
	return json.data if json.data is Dictionary else {}
