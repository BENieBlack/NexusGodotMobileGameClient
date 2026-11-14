## LocalMstItemRepository の単体テスト（SQLite を実際に使う。free-diamond-item client_design.md 5-1・6 節）。
##
## mst_item と mst_item__l10n は同梱 DB に無く、配信があるときだけ更新 DB に入る（必須にしない）。
## 「配信あり」の読み取り（行・言語・NULL）と「配信なし」（同梱 DB・DB 未オープン）で null になることを確かめる。
extends GdUnitTestSuite

const WORK_DIR := "user://test_item_master/"

var _database: MasterDatabase


func before_test() -> void:
	_remove_dir(WORK_DIR)
	_database = MasterDatabase.new()


func after_test() -> void:
	_database.close_all()
	_remove_dir(WORK_DIR)


## 更新 DB（必須 3 テーブル + mst_item）を開く。
func _open_with_items() -> void:
	var base := WORK_DIR + "base.db"
	var items := WORK_DIR + "item.db"
	assert_bool(SqliteTestHelper.create_master_db(base)).is_true()
	assert_bool(SqliteTestHelper.create_item_master_db(items)).is_true()
	var files := {
		"mst_gacha": base,
		"mst_unit": base,
		"mst_equipment": base,
		"mst_item": items,
	}
	assert_bool(_database.open_downloaded(files)).is_true()


## 前提: 配信あり。期待: mst_item の行と、指定言語（ja）の名前が引ける（別言語の名前は混ざらない）。
func test_reads_row_and_name_in_language() -> void:
	_open_with_items()
	var item := LocalMstItemRepository.new(_database, "ja").get_by_id("free_diamond")
	assert_str(item.id).is_equal("free_diamond")
	assert_str(item.type).is_equal("currency")
	assert_int(item.deploy_key).is_equal(1)
	assert_str(item.name).is_equal("無償ダイヤ")
	assert_str(LocalMstItemRepository.new(_database, "en").get_by_id("free_diamond").name).is_equal(
		"Free Diamond"
	)


## 前提: 別言語（en）の行しか無い・name が NULL・l10n の行なし。期待: 行は返り、name は空。
func test_name_is_empty_without_language_row_or_with_null_name() -> void:
	_open_with_items()
	var repository := LocalMstItemRepository.new(_database, "ja")
	assert_object(repository.get_by_id("en_only")).is_not_null()
	assert_str(repository.get_by_id("en_only").name).is_empty()
	assert_str(repository.get_by_id("null_name").name).is_empty()
	assert_str(repository.get_by_id("no_l10n").name).is_empty()


## 前提: mst_item に行が無い ID。期待: null。NULL の列（deploy_key・type）は既定値。
func test_missing_row_is_null_and_null_columns_default() -> void:
	_open_with_items()
	var repository := LocalMstItemRepository.new(_database, "ja")
	assert_object(repository.get_by_id("nope")).is_null()
	var item := repository.get_by_id("null_cols")
	assert_int(item.deploy_key).is_equal(0)
	assert_str(item.type).is_empty()


## 前提: 同梱 DB だけ（mst_item なし）・DB 未オープン。期待: 例外にならず null（フォールバック表示になる）。
func test_returns_null_when_table_is_not_delivered_or_no_database() -> void:
	var bundled := WORK_DIR + "bundled.db"
	assert_bool(SqliteTestHelper.create_master_db(bundled)).is_true()
	assert_bool(_database.open_bundled(bundled)).is_true()
	assert_object(LocalMstItemRepository.new(_database, "ja").get_by_id("free_diamond")).is_null()
	(
		assert_object(
			LocalMstItemRepository.new(MasterDatabase.new(), "ja").get_by_id("free_diamond")
		)
		. is_null()
	)


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)
