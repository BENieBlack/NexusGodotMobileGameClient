extends Node

# テーブルグループ単位のSQLiteマスターデータを管理する。
const BUNDLED_DB_PATH := "res://data/master.db"
const MASTER_DIR := "user://master/"
const HASHES_PATH := "user://master_hashes.json"
const API_BASE_URL := "http://localhost:8090/api"
const MASTER_DATA_BASE_URL := "http://localhost:8091"

var db: SQLite = null
var _database_array: Array[SQLite] = []
var is_initialized := false
var gacha_repository: MstGachaRepository = null
var unit_repository: MstUnitRepository = null
var equipment_repository: MstEquipmentRepository = null

signal master_data_loaded()
signal master_data_load_failed(error: String)
signal download_progress(current: int, total: int, table_name: String)

func _ready() -> void:
	_initialize_bundled_database()

func _initialize_bundled_database() -> void:
	if not ClassDB.class_exists("SQLite"):
		master_data_load_failed.emit("SQLiteプラグインが利用できません")
		return

	var bundled_db := SQLite.new()
	bundled_db.path = BUNDLED_DB_PATH
	if not bundled_db.open_db():
		master_data_load_failed.emit("同梱SQLiteを開けません")
		return

	db = bundled_db
	_database_array = [bundled_db]
	_initialize_repositories(bundled_db, bundled_db, bundled_db)
	is_initialized = true
	master_data_loaded.emit()

## version APIを確認し、変更されたテーブルグループだけ取得する。
## 失敗時は同梱DBを維持し、falseを返す。
func check_and_update() -> bool:
	if not UserDataManager.is_logged_in:
		return false

	var request := HTTPRequest.new()
	add_child(request)
	var headers := PackedStringArray(["Accept: application/json"])
	if UserDataManager.master_hash != "":
		headers.append("X-Master-Hash: " + UserDataManager.master_hash)
	var endpoint := API_BASE_URL + "/auth/version?deploy_version=" + str(UserDataManager.master_deploy_id)
	var request_error := request.request(endpoint, headers, HTTPClient.METHOD_GET)
	if request_error != OK:
		request.queue_free()
		return false

	var result = await request.request_completed
	request.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		return false

	var json := JSON.new()
	if json.parse(result[3].get_string_from_utf8()) != OK or not (json.data is Dictionary):
		return false

	var response_data: Dictionary = json.data
	var needs_update := bool(response_data.get("needs_update", false))
	var master_update_required := bool(response_data.get("master_update_required", false))
	if not needs_update and not master_update_required:
		return true

	var master_data = response_data.get("master", {})
	if not (master_data is Dictionary) or not master_data.has("tables"):
		return false

	var server_table_array: Dictionary = master_data["tables"]
	if server_table_array.is_empty():
		return false
	var local_hash_array := _load_local_hashes()
	var update_table_array: Array = []
	for table_name in server_table_array:
		var table_data: Dictionary = server_table_array[table_name]
		if str(local_hash_array.get(table_name, "")) != str(table_data.get("hash", "")):
			update_table_array.append({"name": table_name, "data": table_data})

	DirAccess.make_dir_recursive_absolute(MASTER_DIR)
	var current := 0
	for table_update in update_table_array:
		current += 1
		var table_name: String = table_update["name"]
		var table_data: Dictionary = table_update["data"]
		download_progress.emit(current, update_table_array.size(), table_name)
		if not await _download_table(table_name, table_data):
			return false
		local_hash_array[table_name] = table_data["hash"]

	_save_local_hashes(local_hash_array)
	if master_data.has("hash"):
		UserDataManager.set_master_hash(str(master_data["hash"]))
	if response_data.has("sys_deploy_id"):
		UserDataManager.set_master_deploy_id(int(response_data["sys_deploy_id"]))
	_reload_downloaded_databases(server_table_array)
	return true

func _download_table(table_name: String, table_data: Dictionary) -> bool:
	var url := str(table_data.get("url", ""))
	if url.begins_with("/"):
		url = MASTER_DATA_BASE_URL + url
	if url == "":
		return false

	var request := HTTPRequest.new()
	add_child(request)
	var request_error := request.request(url, PackedStringArray(["Accept: application/octet-stream"]), HTTPClient.METHOD_GET)
	if request_error != OK:
		request.queue_free()
		return false

	var result = await request.request_completed
	request.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		return false

	var hash_value := str(table_data.get("hash", ""))
	var file_path: String = MASTER_DIR + table_name + "_" + hash_value + ".sqlite"
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(result[3])
	file.close()
	return true

func _reload_downloaded_databases(server_table_array: Dictionary) -> void:
	_close_databases()
	var database_map: Dictionary = {}
	for table_name in server_table_array:
		var hash_value := str(server_table_array[table_name].get("hash", ""))
		var file_path: String = MASTER_DIR + table_name + "_" + hash_value + ".sqlite"
		if not FileAccess.file_exists(file_path):
			continue
		var database := SQLite.new()
		database.path = file_path
		if database.open_db():
			database_map[table_name] = database
			_database_array.append(database)

	# 必須グループが揃わない場合は、同梱DBへ戻して起動不能を避ける。
	if not database_map.has("mst_gacha") or not database_map.has("mst_unit") or not database_map.has("mst_equipment"):
		_close_databases()
		_initialize_bundled_database()
		return

	var gacha_db: SQLite = database_map["mst_gacha"]
	var unit_db: SQLite = database_map["mst_unit"]
	var equipment_db: SQLite = database_map["mst_equipment"]
	_initialize_repositories(gacha_db, unit_db, equipment_db)
	db = unit_db
	is_initialized = true
	master_data_loaded.emit()

func _initialize_repositories(gacha_db: SQLite, unit_db: SQLite, equipment_db: SQLite) -> void:
	gacha_repository = MstGachaRepository.new(gacha_db)
	unit_repository = MstUnitRepository.new(unit_db)
	equipment_repository = MstEquipmentRepository.new(equipment_db)

func _load_local_hashes() -> Dictionary:
	if not FileAccess.file_exists(HASHES_PATH):
		return {}
	var file := FileAccess.open(HASHES_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _save_local_hashes(hash_array: Dictionary) -> void:
	var file := FileAccess.open(HASHES_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(hash_array))
		file.close()

func get_gacha_repository() -> MstGachaRepository:
	return gacha_repository

func get_unit_repository() -> MstUnitRepository:
	return unit_repository

func get_equipment_repository() -> MstEquipmentRepository:
	return equipment_repository

func _close_databases() -> void:
	for database in _database_array:
		if database != null:
			database.close_db()
	_database_array.clear()
	db = null

func _exit_tree() -> void:
	_close_databases()
