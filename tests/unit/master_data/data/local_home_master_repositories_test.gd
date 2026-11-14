## LocalMstPlayerLevelRepository / LocalMstConfigRepository の単体テスト（SQLite を実際に使う）。
##
## 2 つのテーブルは同梱 DB に無く、配信があるときだけ更新 DB に入る（必須にしない）。
## ここでは「配信あり（更新 DB に両テーブルがある）」と「配信なし（同梱 DB・DB 未オープン）」を確かめる。
extends GdUnitTestSuite

const WORK_DIR := "user://test_home_master/"

var _database: MasterDatabase


func before_test() -> void:
	_remove_dir(WORK_DIR)
	_database = MasterDatabase.new()


func after_test() -> void:
	_database.close_all()
	_remove_dir(WORK_DIR)


## 更新 DB（必須 3 テーブル + 2 つの任意テーブル）を開く。
func _open_with_home_tables() -> void:
	var base := WORK_DIR + "base.db"
	var home := WORK_DIR + "home.db"
	assert_bool(SqliteTestHelper.create_master_db(base)).is_true()
	assert_bool(SqliteTestHelper.create_home_master_db(home)).is_true()
	var files := {
		"mst_gacha": base,
		"mst_unit": base,
		"mst_equipment": base,
		"mst_player_level": home,
		"mst_config": home,
	}
	assert_bool(_database.open_downloaded(files)).is_true()


## 前提: 配信あり。期待: レベルの行が読め、無いレベル（最大レベル超過を含む）は null。NULL の列は 0。
func test_player_level_reads_rows() -> void:
	_open_with_home_tables()
	var repository := LocalMstPlayerLevelRepository.new(_database)
	var level1 := repository.get_by_level(1)
	assert_int(level1.level).is_equal(1)
	assert_int(level1.max_stamina).is_equal(50)
	assert_int(repository.get_by_level(2).required_exp).is_equal(100)
	assert_int(repository.get_by_level(2).max_stamina).is_equal(52)
	assert_int(repository.get_by_level(3).max_stamina).is_equal(0)
	assert_object(repository.get_by_level(101)).is_null()


## 前提: 配信あり。期待: 設定値が文字列のまま読め、value_as_int は int 型の整数だけを返す（他は -1）。
func test_config_reads_rows_and_value_types() -> void:
	_open_with_home_tables()
	var repository := LocalMstConfigRepository.new(_database)
	var interval := repository.get_by_id("stamina_recovery_interval_seconds")
	assert_str(interval.value).is_equal("300")
	assert_str(interval.value_type).is_equal("int")
	assert_int(interval.value_as_int()).is_equal(300)
	assert_int(repository.get_by_id("float_value").value_as_int()).is_equal(-1)
	assert_int(repository.get_by_id("broken_int").value_as_int()).is_equal(-1)
	assert_int(repository.get_by_id("null_value").value_as_int()).is_equal(-1)
	assert_str(repository.get_by_id("null_value").value).is_empty()
	# 0 は読めた値として返す（「0 以下は無効」の判断は UseCase が行う）
	assert_int(repository.get_by_id("zero").value_as_int()).is_equal(0)
	assert_object(repository.get_by_id("nope")).is_null()


## 前提: 同梱 DB だけ（両テーブルを含まない）。期待: 例外にならず null。
func test_returns_null_when_tables_are_not_delivered() -> void:
	var bundled := WORK_DIR + "bundled.db"
	assert_bool(SqliteTestHelper.create_master_db(bundled)).is_true()
	assert_bool(_database.open_bundled(bundled)).is_true()
	assert_object(LocalMstPlayerLevelRepository.new(_database).get_by_level(1)).is_null()
	assert_object(LocalMstConfigRepository.new(_database).get_by_id("x")).is_null()


## 前提: DB を開いていない。期待: null。
func test_returns_null_without_database() -> void:
	assert_object(LocalMstPlayerLevelRepository.new(MasterDatabase.new()).get_by_level(1)).is_null()
	assert_object(LocalMstConfigRepository.new(MasterDatabase.new()).get_by_id("x")).is_null()


## MstConfig.value_as_int の型の読み取り（DB を使わない）。
func test_value_as_int_rules() -> void:
	var config := MstConfig.new()
	config.value_type = "int"
	config.value = " 42 "
	assert_int(config.value_as_int()).is_equal(42)
	config.value = "-5"
	assert_int(config.value_as_int()).is_equal(-5)
	config.value = ""
	assert_int(config.value_as_int()).is_equal(-1)
	config.value = "1.0"
	assert_int(config.value_as_int()).is_equal(-1)
	config.value_type = "string"
	config.value = "42"
	assert_int(config.value_as_int()).is_equal(-1)


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub_dir in dir.get_directories():
		_remove_dir(path.path_join(sub_dir))
		dir.remove(sub_dir)
	DirAccess.remove_absolute(path)
