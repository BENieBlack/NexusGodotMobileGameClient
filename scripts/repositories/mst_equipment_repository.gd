class_name MstEquipmentRepository
extends RefCounted

# 装備マスターリポジトリ - SQLiteから装備データを取得

var db: SQLite = null
var cache: Dictionary = {}  # id -> MstEquipment
var cache_all: Array = []  # 全件キャッシュ
var is_cache_loaded: bool = false

func _init(database: SQLite):
	db = database

# 全装備データを取得（キャッシュ付き）
func get_all() -> Array:
	if is_cache_loaded:
		return cache_all
	
	cache_all.clear()
	cache.clear()
	
	var query = """
		SELECT 
			deploy_key, id, type, element, rarity,
			attack, defense, hp, sort_desc, is_active,
			created_at, updated_at
		FROM mst_equipment
		ORDER BY sort_desc DESC, rarity DESC, id ASC
	"""
	
	db.query(query)
	
	for row in db.query_result:
		var equipment = _row_to_model(row)
		cache_all.append(equipment)
		cache[equipment.id] = equipment
	
	is_cache_loaded = true
	print("[MstEquipmentRepository] 全装備データを読み込み: ", cache_all.size(), "件")
	return cache_all

# 有効な装備のみ取得
func get_all_active() -> Array:
	var all_equipment = get_all()
	var active_equipment: Array = []
	
	for equipment in all_equipment:
		if equipment.is_active:
			active_equipment.append(equipment)
	
	return active_equipment

# レアリティでフィルタ
func get_by_rarity(rarity: MstEquipment.Rarity) -> Array:
	var all_equipment = get_all()
	var filtered: Array = []
	
	for equipment in all_equipment:
		if equipment.rarity == rarity:
			filtered.append(equipment)
	
	return filtered

# 属性でフィルタ
func get_by_element(element: MstEquipment.Element) -> Array:
	var all_equipment = get_all()
	var filtered: Array = []
	
	for equipment in all_equipment:
		if equipment.element == element:
			filtered.append(equipment)
	
	return filtered

# タイプでフィルタ
func get_by_type(type: MstEquipment.EquipmentType) -> Array:
	var all_equipment = get_all()
	var filtered: Array = []
	
	for equipment in all_equipment:
		if equipment.type == type:
			filtered.append(equipment)
	
	return filtered

# IDで装備を取得
func get_by_id(equipment_id: String) -> MstEquipment:
	# キャッシュにあればそれを返す
	if cache.has(equipment_id):
		return cache[equipment_id]
	
	# キャッシュがロード済みなら、存在しない
	if is_cache_loaded:
		return null
	
	# DBから取得
	var query = """
		SELECT 
			deploy_key, id, type, element, rarity,
			attack, defense, hp, sort_desc, is_active,
			created_at, updated_at
		FROM mst_equipment
		WHERE id = ?
		LIMIT 1
	"""
	
	db.query_with_bindings(query, [equipment_id])
	
	if db.query_result.size() == 0:
		return null
	
	var equipment = _row_to_model(db.query_result[0])
	cache[equipment.id] = equipment
	return equipment

# 複数IDで取得
func get_by_ids(equipment_ids: Array) -> Array:
	var result: Array = []
	
	for equipment_id in equipment_ids:
		var equipment = get_by_id(str(equipment_id))
		if equipment != null:
			result.append(equipment)
	
	return result

# キャッシュをクリア
func clear_cache() -> void:
	cache.clear()
	cache_all.clear()
	is_cache_loaded = false

# SQLiteの行をMstEquipmentモデルに変換
func _row_to_model(row: Dictionary) -> MstEquipment:
	var equipment = MstEquipment.new()
	
	equipment.deploy_key = int(row.get("deploy_key", 202601010))
	equipment.id = str(row.get("id", ""))
	equipment.type = MstEquipment._parse_equipment_type(str(row.get("type", "Attack")))
	equipment.element = MstEquipment._parse_element(str(row.get("element", "Fire")))
	equipment.rarity = MstEquipment._parse_rarity(str(row.get("rarity", "C")))
	equipment.attack = int(row.get("attack", 0))
	equipment.defense = int(row.get("defense", 0))
	equipment.hp = int(row.get("hp", 0))
	equipment.sort_desc = int(row.get("sort_desc", 0))
	equipment.is_active = bool(row.get("is_active", true))
	equipment.created_at = str(row.get("created_at", ""))
	equipment.updated_at = str(row.get("updated_at", ""))
	
	# TODO: 多言語データ（l10n）の読み込み
	# 現在は簡易的にIDを名前として使用
	equipment.name = equipment.id
	equipment.description = ""
	
	return equipment
