class_name MstGachaRepository
extends RefCounted

# ガチャマスターリポジトリ - SQLiteからガチャデータを取得

var db: SQLite = null
var cache: Dictionary = {}  # id -> MstGacha
var cache_all: Array = []  # 全件キャッシュ
var is_cache_loaded: bool = false

func _init(database: SQLite):
	db = database

# 全ガチャデータを取得（キャッシュ付き）
func get_all() -> Array:
	if is_cache_loaded:
		return cache_all
	
	cache_all.clear()
	cache.clear()
	
	var query = """
		SELECT 
			deploy_key, id, sort_desc, is_active, 
			start_at, end_at, daily_limit, has_step_up,
			created_at, updated_at
		FROM mst_gacha
		ORDER BY sort_desc DESC
	"""
	
	db.query(query)
	
	for row in db.query_result:
		var gacha = _row_to_model(row)
		cache_all.append(gacha)
		cache[gacha.id] = gacha
	
	is_cache_loaded = true
	print("[MstGachaRepository] 全ガチャデータを読み込み: ", cache_all.size(), "件")
	return cache_all

# 有効なガチャのみ取得
func get_all_active() -> Array:
	var all_gachas = get_all()
	var active_gachas: Array = []
	
	for gacha in all_gachas:
		if gacha.is_active:
			active_gachas.append(gacha)
	
	return active_gachas

# IDでガチャを取得
func get_by_id(gacha_id: String) -> MstGacha:
	# キャッシュにあればそれを返す
	if cache.has(gacha_id):
		return cache[gacha_id]
	
	# キャッシュがロード済みなら、存在しない
	if is_cache_loaded:
		return null
	
	# DBから取得
	var query = """
		SELECT 
			deploy_key, id, sort_desc, is_active, 
			start_at, end_at, daily_limit, has_step_up,
			created_at, updated_at
		FROM mst_gacha
		WHERE id = ?
		LIMIT 1
	"""
	
	db.query_with_bindings(query, [gacha_id])
	
	if db.query_result.size() == 0:
		return null
	
	var gacha = _row_to_model(db.query_result[0])
	cache[gacha.id] = gacha
	return gacha

# 複数IDで取得
func get_by_ids(gacha_ids: Array) -> Array:
	var result: Array = []
	
	for gacha_id in gacha_ids:
		var gacha = get_by_id(str(gacha_id))
		if gacha != null:
			result.append(gacha)
	
	return result

# キャッシュをクリア
func clear_cache() -> void:
	cache.clear()
	cache_all.clear()
	is_cache_loaded = false

# SQLiteの行をMstGachaモデルに変換
func _row_to_model(row: Dictionary) -> MstGacha:
	var gacha = MstGacha.new()
	
	gacha.deploy_key = int(row.get("deploy_key", 202601010))
	gacha.id = str(row.get("id", ""))
	gacha.sort_desc = int(row.get("sort_desc", 0))
	gacha.is_active = bool(row.get("is_active", true))
	gacha.start_at = str(row.get("start_at", "")) if row.get("start_at") != null else ""
	gacha.end_at = str(row.get("end_at", "")) if row.get("end_at") != null else ""
	gacha.daily_limit = int(row.get("daily_limit", 0))
	gacha.has_step_up = bool(row.get("has_step_up", false))
	gacha.created_at = str(row.get("created_at", ""))
	gacha.updated_at = str(row.get("updated_at", ""))
	
	# TODO: 多言語データ（l10n）の読み込み
	# 現在は簡易的にIDを名前として使用
	gacha.name = gacha.id
	gacha.description = ""
	
	return gacha
