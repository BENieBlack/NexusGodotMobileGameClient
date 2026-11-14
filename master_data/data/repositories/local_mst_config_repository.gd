## 設定マスター（mst_config）を SQLite から読む（MstConfigRepository の実装）。
##
## このテーブルは同梱 DB に無く、配信があるときだけ更新 DB に入る（必須テーブルにしない。7 節）。
## 配信が無い・テーブルが無いときは MasterDatabase.select_rows が空配列を返すので、null を返すだけ。
## value は文字列のまま読む（型の解釈は MstConfig.value_as_int）。キャッシュは持たない。
class_name LocalMstConfigRepository
extends MstConfigRepository

const TABLE := "mst_config"
const COLUMNS := "deploy_key, id, value, value_type"

var _database: MasterDatabase


func _init(database: MasterDatabase) -> void:
	_database = database


func get_by_id(id: String) -> MstConfig:
	var sql := "SELECT %s FROM %s WHERE id = ? LIMIT 1" % [COLUMNS, TABLE]
	var rows := _database.select_rows(TABLE, sql, [id])
	if rows.is_empty():
		return null
	return _row_to_model(rows[0])


## SQLite の 1 行（Dictionary）を読み取りモデルに直す。NULL は既定値（空文字・0）。
## value は SQLite が整数型で返すことがあるので str() で文字列に揃える（null は空文字にする）。
func _row_to_model(row: Dictionary) -> MstConfig:
	var model := MstConfig.new()
	var raw_key: Variant = row.get("deploy_key", null)
	model.deploy_key = 0 if raw_key == null else int(raw_key)
	var raw_id: Variant = row.get("id", null)
	model.id = "" if raw_id == null else str(raw_id)
	var raw_value: Variant = row.get("value", null)
	model.value = "" if raw_value == null else str(raw_value)
	var raw_type: Variant = row.get("value_type", null)
	model.value_type = "" if raw_type == null else str(raw_type)
	return model
