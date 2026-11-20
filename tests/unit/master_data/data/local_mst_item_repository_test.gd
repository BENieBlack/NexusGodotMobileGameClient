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


## 前提: is_wallet の列がある mst_item（0/1 の整数・NULL）。期待: 0 以外は真、0・NULL は偽の真偽値になる。
func test_is_wallet_is_converted_to_bool() -> void:
	var items := WORK_DIR + "wallet_item.db"
	(
		assert_bool(
			(
				SqliteTestHelper
				. create_db(
					items,
					[
						(
							"CREATE TABLE mst_item (deploy_key INTEGER, id TEXT PRIMARY KEY, type TEXT, "
							+ "is_wallet INTEGER)"
						),
						"INSERT INTO mst_item VALUES (1, 'gold', 'currency', 1)",
						"INSERT INTO mst_item VALUES (1, 'potion', 'recovery', 0)",
						"INSERT INTO mst_item VALUES (1, 'nullable', 'recovery', NULL)",
						(
							"CREATE TABLE mst_item__l10n (deploy_key INTEGER, mst_item_id TEXT, "
							+ "language TEXT, name TEXT)"
						),
					]
				)
			)
		)
		. is_true()
	)
	_open_downloaded_with(items)
	var repository := LocalMstItemRepository.new(_database, "ja")
	assert_bool(repository.get_by_id("gold").is_wallet).is_true()
	assert_bool(repository.get_by_id("potion").is_wallet).is_false()
	assert_bool(repository.get_by_id("nullable").is_wallet).is_false()
	# 既存の列も読める（SELECT * にしても壊れない）
	assert_str(repository.get_by_id("gold").type).is_equal("currency")


## 前提: is_wallet の列が無い古い配信ファイルの mst_item（既存の create_item_master_db）。
## 期待: get_by_id が行を引け（全件が引けなくなる退行を防ぐ）、is_wallet は偽。
func test_old_delivery_without_is_wallet_column_is_still_readable() -> void:
	_open_with_items()
	var item := LocalMstItemRepository.new(_database, "ja").get_by_id("free_diamond")
	assert_object(item).is_not_null()
	assert_str(item.name).is_equal("無償ダイヤ")
	assert_bool(item.is_wallet).is_false()


func _open_downloaded_with(items: String) -> void:
	var base := WORK_DIR + "base2.db"
	assert_bool(SqliteTestHelper.create_master_db(base)).is_true()
	var files := {"mst_gacha": base, "mst_unit": base, "mst_equipment": base, "mst_item": items}
	assert_bool(_database.open_downloaded(files)).is_true()


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)
