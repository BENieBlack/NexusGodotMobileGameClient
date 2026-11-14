## 設定マスター（mst_config）の読み取りモデル（1 行 = 1 つの設定値）。
##
## value は DB の文字列のまま持ち、value_type（"int" など）はサーバーが配信する型の名前。
## 読み取りの変換（value_as_int）だけを持ち、「0 以下は無効」のような判断は使う側の UseCase が行う。
class_name MstConfig
extends RefCounted

const TYPE_INT := "int"
## 整数として読めなかったことを表す値
const NOT_AN_INT := -1

var deploy_key: int = 0
var id: String = ""
var value: String = ""
var value_type: String = ""


## value_type が "int" で、value が整数の文字列（符号つき可）に読めるときだけその値を返す。
## それ以外（型が違う・空・小数・文字混じり）は -1。負の整数はそのまま返る（-1 と区別できないので、
## 有効かどうか（1 以上など）の判断は呼び出し側が行う）。
func value_as_int() -> int:
	if value_type != TYPE_INT:
		return NOT_AN_INT
	var text := value.strip_edges()
	if not text.is_valid_int():
		return NOT_AN_INT
	return text.to_int()
