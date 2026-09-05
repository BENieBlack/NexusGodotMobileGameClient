class_name MstUnitRepository
extends RefCounted

# ユニットマスターリポジトリ - SQLiteからユニットデータを取得

var db: SQLite = null
var cache: Dictionary = {}  # id -> MstUnit
var cache_all: Array = []  # 全件キャッシュ
var is_cache_loaded: bool = false

func _init(database: SQLite):
	db = database

# 全ユニットデータを取得（キャッシュ付き）
func get_all() -> Array:
	if is_cache_loaded:
		return cache_all
	
	cache_all.clear()
	cache.clear()
	
	var query = """
		SELECT 
			deploy_key, id, type, element, rarity,
			created_at, updated_at
		FROM mst_unit
		ORDER BY rarity DESC, id ASC
	"""
	
	db.query(query)
	
	for row in db.query_result:
		var unit = _row_to_model(row)
		cache_all.append(unit)
		cache[unit.id] = unit
	
	is_cache_loaded = true
	print("[MstUnitRepository] 全ユニットデータを読み込み: ", cache_all.size(), "件")
	return cache_all

# レアリティでフィルタ
func get_by_rarity(rarity: MstUnit.Rarity) -> Array:
	var all_units = get_all()
	var filtered: Array = []
	
	for unit in all_units:
		if unit.rarity == rarity:
			filtered.append(unit)
	
	return filtered

# 属性でフィルタ
func get_by_element(element: MstUnit.Element) -> Array:
	var all_units = get_all()
	var filtered: Array = []
	
	for unit in all_units:
		if unit.element == element:
			filtered.append(unit)
	
	return filtered

# IDでユニットを取得
func get_by_id(unit_id: String) -> MstUnit:
	# キャッシュにあればそれを返す
	if cache.has(unit_id):
		return cache[unit_id]
	
	# キャッシュがロード済みなら、存在しない
	if is_cache_loaded:
		return null
	
	# DBから取得
	var query = """
		SELECT 
			deploy_key, id, type, element, rarity,
			created_at, updated_at
		FROM mst_unit
		WHERE id = ?
		LIMIT 1
	"""
	
	db.query_with_bindings(query, [unit_id])
	
	if db.query_result.size() == 0:
		return null
	
	var unit = _row_to_model(db.query_result[0])
	cache[unit.id] = unit
	return unit

# 複数IDで取得
func get_by_ids(unit_ids: Array) -> Array:
	var result: Array = []
	
	for unit_id in unit_ids:
		var unit = get_by_id(str(unit_id))
		if unit != null:
			result.append(unit)
	
	return result

# キャッシュをクリア
func clear_cache() -> void:
	cache.clear()
	cache_all.clear()
	is_cache_loaded = false

# SQLiteの行をMstUnitモデルに変換
func _row_to_model(row: Dictionary) -> MstUnit:
	var unit = MstUnit.new()
	
	unit.deploy_key = int(row.get("deploy_key", 202601010))
	unit.id = str(row.get("id", ""))
	unit.type = MstUnit._parse_unit_type(str(row.get("type", "Attack")))
	unit.element = MstUnit._parse_element(str(row.get("element", "Fire")))
	unit.rarity = MstUnit._parse_rarity(str(row.get("rarity", "C")))
	unit.created_at = str(row.get("created_at", ""))
	unit.updated_at = str(row.get("updated_at", ""))
	
	# TODO: 多言語データ（l10n）の読み込み
	# 現在は簡易的にIDを名前として使用
	unit.name = unit.id
	unit.description = ""
	
	return unit
