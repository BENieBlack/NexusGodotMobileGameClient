## ユニットマスター（mst_unit）を SQLite から読む（MasterUnitRepository の実装）。
##
## 読むのは MasterDatabase 経由で、DB が同梱 DB から更新 DB に切り替わっても、そのまま最新を読める。
## キャッシュは持たない（最小。旧実装のキャッシュは、DB の切り替えで古くなる落とし穴があった）。
## 並び: レアリティの高い順（UR → C）、同じなら id 昇順。旧実装の ORDER BY（rarity DESC）は文字列順で、
##   "UR" > "UC" > "SSR" ... と意味の順にならない。ここでは意味の順に並べる。
class_name LocalMasterUnitRepository
extends MasterUnitRepository

const TABLE := "mst_unit"
const COLUMNS := "deploy_key, id, type, element, rarity"
## レアリティの強さ順（弱 → 強）。SQL の CASE で数値に直して降順に並べる
const RARITY_ORDER_SQL := (
	"CASE rarity WHEN 'C' THEN 0 WHEN 'UC' THEN 1 WHEN 'R' THEN 2 "
	+ "WHEN 'SR' THEN 3 WHEN 'SSR' THEN 4 WHEN 'UR' THEN 5 ELSE -1 END"
)

var _database: MasterDatabase


func _init(database: MasterDatabase) -> void:
	_database = database


func get_all() -> Array[MasterUnit]:
	var sql := "SELECT %s FROM %s ORDER BY %s DESC, id ASC" % [COLUMNS, TABLE, RARITY_ORDER_SQL]
	var units: Array[MasterUnit] = []
	for row: Dictionary in _database.select_rows(TABLE, sql):
		units.append(_row_to_model(row))
	return units


func get_by_id(id: String) -> MasterUnit:
	var sql := "SELECT %s FROM %s WHERE id = ? LIMIT 1" % [COLUMNS, TABLE]
	var rows := _database.select_rows(TABLE, sql, [id])
	if rows.is_empty():
		return null
	return _row_to_model(rows[0])


## SQLite の 1 行（Dictionary）を読み取りモデルに直す。NULL は既定値（D3 と同じ考え方）。
func _row_to_model(row: Dictionary) -> MasterUnit:
	var unit := MasterUnit.new()
	unit.id = str(row.get("id", ""))
	unit.deploy_key = int(row.get("deploy_key", 0))
	unit.type = str(row.get("type", ""))
	unit.element = str(row.get("element", ""))
	unit.rarity = str(row.get("rarity", ""))
	return unit
