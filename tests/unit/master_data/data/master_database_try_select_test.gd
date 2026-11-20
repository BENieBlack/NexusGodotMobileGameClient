## MasterDatabase.try_select_rows の単体テスト（失敗と 0 件の区別。client_design.md 2-4）。
##
## select_rows は失敗を空配列にするので「0 件」と「読めない」が同じに見える。try_select_rows は
## 失敗（DB 未オープン・テーブルなし・列なし）を ok = false、0 件を ok = true で区別する。
extends GdUnitTestSuite

const WORK_DIR := "user://test_try_select/"

var _database: MasterDatabase


func before_test() -> void:
	_remove_dir(WORK_DIR)
	_database = MasterDatabase.new()
	var base := WORK_DIR + "base.db"
	assert_bool(SqliteTestHelper.create_master_db(base)).is_true()
	assert_bool(_database.open_bundled(base)).is_true()


func after_test() -> void:
	_database.close_all()
	_remove_dir(WORK_DIR)


## 前提: 行のあるテーブル。操作: try_select_rows。期待: ok = true と行（select_rows と同じ中身）。
func test_success_returns_rows() -> void:
	var result := _database.try_select_rows("mst_unit", "SELECT id FROM mst_unit ORDER BY id")
	assert_bool(result.ok).is_true()
	assert_int(result.rows.size()).is_equal(3)
	assert_str(result.rows[0]["id"]).is_equal("u1")


## 前提: 条件に合う行が無い。期待: ok = true で rows は空（失敗ではない）。
func test_zero_rows_is_still_ok() -> void:
	var result := _database.try_select_rows(
		"mst_unit", "SELECT id FROM mst_unit WHERE id = ?", ["none"]
	)
	assert_bool(result.ok).is_true()
	assert_array(result.rows).is_empty()


## 前提: 存在しない列・存在しないテーブル（古い配信ファイルの列なしを想定）。
## 期待: ok = false（select_rows だと空配列で、0 件と見分けがつかない）。
func test_missing_column_or_table_is_failure() -> void:
	var no_column := _database.try_select_rows("mst_unit", "SELECT sort_desc FROM mst_unit")
	assert_bool(no_column.ok).is_false()
	assert_array(no_column.rows).is_empty()
	var no_table := _database.try_select_rows("mst_unit", "SELECT id FROM no_such_table")
	assert_bool(no_table.ok).is_false()
	# 既存の select_rows は変わらず空配列（同じ失敗を空配列で返す）
	assert_array(_database.select_rows("mst_unit", "SELECT sort_desc FROM mst_unit")).is_empty()


## 前提: そのテーブルの DB を開いていない（未配信）・DB 未オープン。期待: ok = false。
func test_unopened_table_or_database_is_failure() -> void:
	assert_bool(_database.try_select_rows("mst_item", "SELECT * FROM mst_item").ok).is_false()
	assert_bool(MasterDatabase.new().try_select_rows("mst_unit", "SELECT 1").ok).is_false()


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)
