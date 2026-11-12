## ガチャマスター（mst_gacha）を SQLite から読む（MasterGachaRepository の実装）。
##
## 読み方・キャッシュなしの理由は local_master_unit_repository.gd と同じ。
## 並び: sort_desc 降順、同じなら id 昇順（仮置き）。
## start_at / end_at は NULL（期限なし）を空文字にして持つ。
class_name LocalMasterGachaRepository
extends MasterGachaRepository

const TABLE := "mst_gacha"
const COLUMNS := "deploy_key, id, sort_desc, is_active, start_at, end_at, daily_limit, has_step_up"

var _database: MasterDatabase


func _init(database: MasterDatabase) -> void:
	_database = database


func get_all() -> Array[MasterGacha]:
	var sql := "SELECT %s FROM %s ORDER BY sort_desc DESC, id ASC" % [COLUMNS, TABLE]
	var gachas: Array[MasterGacha] = []
	for row: Dictionary in _database.select_rows(TABLE, sql):
		gachas.append(_row_to_model(row))
	return gachas


func get_by_id(id: String) -> MasterGacha:
	var sql := "SELECT %s FROM %s WHERE id = ? LIMIT 1" % [COLUMNS, TABLE]
	var rows := _database.select_rows(TABLE, sql, [id])
	if rows.is_empty():
		return null
	return _row_to_model(rows[0])


func _row_to_model(row: Dictionary) -> MasterGacha:
	var gacha := MasterGacha.new()
	gacha.id = str(row.get("id", ""))
	gacha.deploy_key = int(row.get("deploy_key", 0))
	gacha.sort_desc = int(row.get("sort_desc", 0))
	gacha.is_active = int(row.get("is_active", 1)) != 0
	# NULL は null のまま str() すると "<null>" になるので、null を明示的に空文字にする
	var start_at: Variant = row.get("start_at", null)
	var end_at: Variant = row.get("end_at", null)
	gacha.start_at = "" if start_at == null else str(start_at)
	gacha.end_at = "" if end_at == null else str(end_at)
	gacha.daily_limit = int(row.get("daily_limit", 0))
	gacha.has_step_up = int(row.get("has_step_up", 0)) != 0
	return gacha
