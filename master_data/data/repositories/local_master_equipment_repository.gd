## 装備マスター（mst_equipment）を SQLite から読む（MasterEquipmentRepository の実装）。
##
## 読み方・キャッシュなしの理由は local_master_unit_repository.gd と同じ。
## 並び: sort_desc 降順、同じなら id 昇順。旧実装は sort_desc → rarity（文字列順）→ id だったが、
## 文字列順のレアリティは意味の順にならないので外した（仮置き）。
class_name LocalMasterEquipmentRepository
extends MasterEquipmentRepository

const TABLE := "mst_equipment"
const COLUMNS := "deploy_key, id, type, element, rarity, attack, defense, hp, sort_desc, is_active"

var _database: MasterDatabase


func _init(database: MasterDatabase) -> void:
	_database = database


func get_all() -> Array[MasterEquipment]:
	var sql := "SELECT %s FROM %s ORDER BY sort_desc DESC, id ASC" % [COLUMNS, TABLE]
	var equipments: Array[MasterEquipment] = []
	for row: Dictionary in _database.select_rows(TABLE, sql):
		equipments.append(_row_to_model(row))
	return equipments


func get_by_id(id: String) -> MasterEquipment:
	var sql := "SELECT %s FROM %s WHERE id = ? LIMIT 1" % [COLUMNS, TABLE]
	var rows := _database.select_rows(TABLE, sql, [id])
	if rows.is_empty():
		return null
	return _row_to_model(rows[0])


func _row_to_model(row: Dictionary) -> MasterEquipment:
	var equipment := MasterEquipment.new()
	equipment.id = str(row.get("id", ""))
	equipment.deploy_key = int(row.get("deploy_key", 0))
	equipment.type = str(row.get("type", ""))
	equipment.element = str(row.get("element", ""))
	equipment.rarity = str(row.get("rarity", ""))
	equipment.attack = int(row.get("attack", 0))
	equipment.defense = int(row.get("defense", 0))
	equipment.hp = int(row.get("hp", 0))
	equipment.sort_desc = int(row.get("sort_desc", 0))
	# SQLite の真偽は 0 / 1 の整数。NULL（キー無し扱い）は有効として読む（旧モデルの既定値 true）
	equipment.is_active = int(row.get("is_active", 1)) != 0
	return equipment
