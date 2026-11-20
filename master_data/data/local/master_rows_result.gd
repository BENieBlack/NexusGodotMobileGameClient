## MasterDatabase.try_select_rows の結果（成功か失敗か、成功なら行）。
##
## 目的: select_rows は失敗（DB が開けない・列が無い・テーブルが無い）を空配列にして返すので、
##       「行が 0 件」と「読めなかった」を区別できない。古い配信ファイル（新しい列が無い）を
##       見分けて再取得につなげるため、失敗と 0 件を別の値で返す（client_design.md 2-4）。
## 項目:
##   ok    問い合わせが成功したか。DB が開けていない・クエリが失敗（列なしなど）なら false
##   rows  成功のときの行（Dictionary の配列）。0 件でも ok = true。失敗のときは空配列
class_name MasterRowsResult
extends RefCounted

var ok: bool = false
var rows: Array = []


func _init(p_ok: bool = false, p_rows: Array = []) -> void:
	ok = p_ok
	rows = p_rows
