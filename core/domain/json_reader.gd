## JSON 由来の Dictionary から値を安全に読む（client_design.md 4 節 D3）。
##
## 目的: サーバーは「キーが無い」と「値が null」を区別しない運用なので、クライアントも同じに扱い、
##       型付きの変数へ null を渡して型エラーになる事故（旧 `.get("x", [])` の落とし穴）を防ぐ。
##       `Dictionary.get(key, [])` は、キーが在って値が null のとき null を返してしまう。
## 範囲: 最小。一覧（get_array）と入れ子の辞書（get_dict）だけ。文字列・数値は必要になった時点で足す。
## 使う場所: 各コンテキスト・master_data の data/api の応答変換だけ。
## 型が違うとき（配列のはずが文字列など）は、既定値を返して警告を出す（サーバー仕様の変化に気づくため）。
class_name JsonReader
extends RefCounted


## key の値を Array で返す。キー無し・null・型違いは空配列。
static func get_array(data: Dictionary, key: String) -> Array:
	var value: Variant = data.get(key, null)
	if value == null:
		return []
	if value is Array:
		return value
	push_warning("JsonReader: %s は配列のはずが %s でした" % [key, type_string(typeof(value))])
	return []


## key の値を Dictionary で返す。キー無し・null・型違いは空の辞書。
static func get_dict(data: Dictionary, key: String) -> Dictionary:
	var value: Variant = data.get(key, null)
	if value == null:
		return {}
	if value is Dictionary:
		return value
	push_warning("JsonReader: %s は辞書のはずが %s でした" % [key, type_string(typeof(value))])
	return {}
