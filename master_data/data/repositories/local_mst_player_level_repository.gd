## プレイヤーレベルマスター（mst_player_level）を SQLite から読む（MstPlayerLevelRepository の実装）。
##
## このテーブルは同梱 DB に無く、配信があるときだけ更新 DB に入る（必須テーブルにしない。7 節）。
## 配信が無い・テーブルが無いときは MasterDatabase.select_rows が空配列を返すので、null を返すだけ。
## キャッシュは持たない（DB の切り替えで古くならないように。LocalMstUnitRepository と同じ）。
class_name LocalMstPlayerLevelRepository
extends MstPlayerLevelRepository

const TABLE := "mst_player_level"
const COLUMNS := "deploy_key, level, required_exp, max_stamina"

var _database: MasterDatabase


func _init(database: MasterDatabase) -> void:
	_database = database


func get_by_level(level: int) -> MstPlayerLevel:
	var sql := "SELECT %s FROM %s WHERE level = ? LIMIT 1" % [COLUMNS, TABLE]
	var rows := _database.select_rows(TABLE, sql, [level])
	if rows.is_empty():
		return null
	return _row_to_model(rows[0])


## SQLite の 1 行（Dictionary）を読み取りモデルに直す。NULL は既定値（0）。
func _row_to_model(row: Dictionary) -> MstPlayerLevel:
	var model := MstPlayerLevel.new()
	model.deploy_key = _int_or_zero(row.get("deploy_key", null))
	model.level = _int_or_zero(row.get("level", null))
	model.required_exp = _int_or_zero(row.get("required_exp", null))
	model.max_stamina = _int_or_zero(row.get("max_stamina", null))
	return model


## NULL（null）は 0。int(null) は実行時エラーになるので、先に分ける。
func _int_or_zero(value: Variant) -> int:
	return 0 if value == null else int(value)
