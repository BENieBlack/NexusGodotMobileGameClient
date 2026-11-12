## LocalMasterDataRepository / MasterDatabase / mst Repository の単体テスト（SQLite を実際に使う）。
##
## user:// の下に、このテスト専用のディレクトリを作って使い、終わったら消す（実機の user://master を汚さない）。
## 同梱 DB は、テスト用に行入りで作ったファイルを bundled_path に渡して代用する（本物の data/master.db は行が空）。
extends GdUnitTestSuite

const WORK_DIR := "user://test_master_data/"

var _database: MasterDatabase
var _bundled_path: String
var _state_path: String
var _master_dir: String


func before_test() -> void:
	_remove_dir(WORK_DIR)
	_master_dir = WORK_DIR + "master/"
	_state_path = WORK_DIR + "state.json"
	_bundled_path = WORK_DIR + "bundled.db"
	assert_bool(SqliteTestHelper.create_master_db(_bundled_path)).is_true()
	_database = MasterDatabase.new()


func after_test() -> void:
	_database.close_all()
	_remove_dir(WORK_DIR)


## 前提: 保存が何も無い。操作: initialize。
## 期待: 同梱 DB を開き（is_bundled）、deploy_id は 0、master_hash は空。
func test_initialize_without_state_opens_bundled() -> void:
	var repository := _new_repository()
	assert_bool(repository.initialize()).is_true()
	assert_bool(_database.is_bundled()).is_true()
	assert_int(repository.deploy_id()).is_equal(0)
	assert_str(repository.master_hash()).is_empty()


## 前提: 3 テーブルのファイルを保存して commit_update。操作: commit_update → 新しい Repository で initialize。
## 期待: commit で更新 DB に切り替わり、状態（deploy_id・master_hash・ハッシュ）が保存される。
## 次の起動（別インスタンス）でも、同梱ではなく更新 DB から始まる（旧実装は起動のたびに同梱へ戻っていた）。
func test_commit_switches_to_downloaded_and_persists() -> void:
	var repository := _new_repository()
	repository.initialize()
	var version := _make_version()
	_save_all_tables(repository, version)

	assert_bool(repository.commit_update(version)).is_true()
	assert_bool(_database.is_bundled()).is_false()
	assert_int(repository.deploy_id()).is_equal(11)
	assert_str(repository.master_hash()).is_equal("mh")
	assert_str(str(repository.table_hashes()["mst_unit"])).is_equal("hu")

	_database.close_all()
	var restarted := _new_repository()
	assert_int(restarted.deploy_id()).is_equal(11)
	assert_bool(restarted.initialize()).is_true()
	assert_bool(_database.is_bundled()).is_false()


## 前提: 必須の 3 テーブルのうち mst_unit のファイルしか無い。操作: commit_update。
## 期待: false。同梱 DB に戻り、保存（deploy_id・ハッシュ）は更新しない。
## 必須グループが揃わないまま切り替えると画面が空になる（旧実装の「同梱 DB へ戻す」の継承）。
func test_commit_without_required_tables_falls_back_to_bundled() -> void:
	var repository := _new_repository()
	repository.initialize()
	var version := MasterVersion.new()
	version.needs_update = true
	version.sys_deploy_id = 11
	version.master_hash = "mh"
	version.tables = [MasterTable.new("mst_unit", "hu", "/x", 1)]
	repository.save_table_file("mst_unit", "hu", FileAccess.get_file_as_bytes(_bundled_path))

	assert_bool(repository.commit_update(version)).is_false()
	assert_bool(_database.is_bundled()).is_true()
	assert_int(repository.deploy_id()).is_equal(0)
	assert_dict(repository.table_hashes()).is_empty()


## 前提: 保存済みの状態があるが、ファイルが消えている。操作: initialize。期待: 同梱 DB で続行する。
func test_initialize_falls_back_when_downloaded_file_is_missing() -> void:
	var repository := _new_repository()
	repository.initialize()
	var version := _make_version()
	_save_all_tables(repository, version)
	repository.commit_update(version)
	_database.close_all()
	_remove_dir(_master_dir)

	var restarted := _new_repository()
	assert_bool(restarted.initialize()).is_true()
	assert_bool(_database.is_bundled()).is_true()


## 前提: 同梱 DB に行がある（テスト用）。操作: 3 つの mst Repository で読む。
## 期待: get_all の並び（ユニットはレアリティの強い順）、get_by_id、NULL の日付は空文字、
##   is_active の 0/1 が bool になる。無い id は null。
func test_mst_repositories_read_rows() -> void:
	_new_repository().initialize()
	var units := LocalMasterUnitRepository.new(_database)
	var ids: Array[String] = []
	for unit in units.get_all():
		ids.append(unit.id)
	assert_array(ids).contains_exactly(["u2", "u1", "u3"])
	assert_str(units.get_by_id("u1").element).is_equal("Fire")
	assert_object(units.get_by_id("nope")).is_null()

	var equipments := LocalMasterEquipmentRepository.new(_database)
	assert_int(equipments.get_all().size()).is_equal(2)
	var equipment := equipments.get_by_id("e2")
	assert_bool(equipment.is_active).is_false()
	assert_int(equipments.get_by_id("e1").attack).is_equal(10)

	var gachas := LocalMasterGachaRepository.new(_database)
	var gacha := gachas.get_by_id("g1")
	assert_str(gacha.start_at).is_empty()
	assert_int(gacha.daily_limit).is_equal(3)
	assert_bool(gacha.has_step_up).is_true()


## 前提: DB を開いていない。操作: mst Repository で読む。期待: 例外にならず空 / null。
func test_mst_repositories_return_empty_without_database() -> void:
	var units := LocalMasterUnitRepository.new(MasterDatabase.new())
	assert_array(units.get_all()).is_empty()
	assert_object(units.get_by_id("u1")).is_null()


## 前提: 保存済みの状態があり、ファイルが全部消えている（deploy_id はサーバーの最新と同じ）。
## 操作: initialize。期待: 同梱 DB で動き、deploy_id と master_hash は「未取得」に戻る。
## 戻さないと、サーバーが needs_update = false を返し続け、欠けたファイルを永遠に取り直せない。
func test_initialize_resets_deploy_id_when_files_are_missing() -> void:
	var repository := _new_repository()
	repository.initialize()
	var version := _make_version()
	_save_all_tables(repository, version)
	repository.commit_update(version)
	_database.close_all()
	_remove_dir(_master_dir)

	var restarted := _new_repository()
	restarted.initialize()
	assert_int(restarted.deploy_id()).is_equal(0)
	assert_str(restarted.master_hash()).is_empty()
	# 次の起動でも未取得のまま（リセットが保存されている）
	assert_int(_new_repository().deploy_id()).is_equal(0)


## 前提: 必須 3 テーブルのファイルはあるが、保存のハッシュにある任意テーブル（mst_item）のファイルが無い。
## 操作: initialize。期待: 更新 DB を開く（同梱へ戻らない）。deploy_id は未取得に戻り、再取得される。
## 「files.size() == hashes.size()」を条件にしていた旧版は、任意テーブルが 1 つ欠けるだけで
## 同梱 DB に戻り続けた。
func test_initialize_keeps_downloaded_when_only_optional_table_is_missing() -> void:
	var repository := _new_repository()
	repository.initialize()
	var version := _make_version()
	version.tables.append(MasterTable.new("mst_item", "hi", "/x", 1))
	_save_all_tables(repository, version)
	repository.commit_update(version)
	_database.close_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_master_dir + "mst_item_hi.sqlite"))

	var restarted := _new_repository()
	assert_bool(restarted.initialize()).is_true()
	assert_bool(_database.is_bundled()).is_false()
	assert_int(restarted.deploy_id()).is_equal(0)
	assert_bool(restarted.has_table_file("mst_item", "hi")).is_false()
	assert_bool(restarted.has_table_file("mst_unit", "hu")).is_true()


## 前提: 古いハッシュのファイルと書きかけの .tmp が残っている。操作: commit_update。
## 期待: 現行ハッシュのファイルだけ残り、古いファイルと .tmp は消える（容量を増やし続けない）。
func test_commit_removes_stale_files() -> void:
	var repository := _new_repository()
	repository.initialize()
	var version := _make_version()
	var bytes := FileAccess.get_file_as_bytes(_bundled_path)
	assert_bool(repository.save_table_file("mst_unit", "old", bytes)).is_true()
	_save_all_tables(repository, version)
	var leftover := FileAccess.open(_master_dir + "mst_unit_zzz.sqlite.tmp", FileAccess.WRITE)
	leftover.store_string("x")
	leftover.close()

	assert_bool(repository.commit_update(version)).is_true()
	assert_bool(repository.has_table_file("mst_unit", "old")).is_false()
	assert_bool(repository.has_table_file("mst_unit", "hu")).is_true()
	assert_bool(FileAccess.file_exists(_master_dir + "mst_unit_zzz.sqlite.tmp")).is_false()


## 前提: 保存先の名前に、同名のディレクトリが既にある（rename で確定できない）。
## 操作: save_table_file。期待: false（書き込み・確定の失敗を成功と誤認しない）。一時ファイルも残さない。
func test_save_table_file_reports_failure_and_cleans_temp() -> void:
	var repository := _new_repository()
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_master_dir + "mst_unit_h.sqlite")
	)
	assert_bool(repository.save_table_file("mst_unit", "h", PackedByteArray([1]))).is_false()
	assert_bool(FileAccess.file_exists(_master_dir + "mst_unit_h.sqlite.tmp")).is_false()


## 前提: 正常な保存。操作: save_table_file。期待: 確定後のファイルがあり、.tmp は残らない。
func test_save_table_file_leaves_no_temp_file() -> void:
	var repository := _new_repository()
	assert_bool(repository.save_table_file("mst_unit", "h", PackedByteArray([1, 2]))).is_true()
	assert_bool(repository.has_table_file("mst_unit", "h")).is_true()
	assert_bool(FileAccess.file_exists(_master_dir + "mst_unit_h.sqlite.tmp")).is_false()


## 前提: 更新 DB（行入り）を開いている。操作: 2 番目のファイルを開けないパスにした
##   open_downloaded を呼ぶ。期待: false で、旧 DB のまま（is_bundled が変わらず、旧 DB から読める）。
## 新しい接続の途中で失敗して旧 DB を閉じてしまうと、画面が空になるため。
func test_open_downloaded_keeps_old_database_when_a_later_file_is_broken() -> void:
	assert_bool(_database.open_bundled(_bundled_path)).is_true()
	# 存在しないディレクトリのパスは、SQLite が開けない（open_db が false）。壊れた中身のファイルは
	# 開く時点では成功し、最初の問い合わせで初めて失敗するので、失敗の再現には向かない
	var broken_path := WORK_DIR + "no_such_dir/x.sqlite"

	# Dictionary は挿入順に開く。mst_unit（正常）→ mst_gacha（不正）の順で、2 番目で失敗させる
	var files := {
		"mst_unit": _bundled_path,
		"mst_gacha": broken_path,
		"mst_equipment": _bundled_path,
	}
	assert_bool(_database.open_downloaded(files)).is_false()
	assert_bool(_database.is_bundled()).is_true()
	var rows := _database.select_rows("mst_unit", "SELECT id FROM mst_unit")
	assert_int(rows.size()).is_equal(3)


func _new_repository() -> LocalMasterDataRepository:
	return LocalMasterDataRepository.new(_database, _master_dir, _state_path, _bundled_path)


## 3 つの必須テーブルを持つ MasterVersion（deploy_id 11、master_hash "mh"）。
func _make_version() -> MasterVersion:
	var version := MasterVersion.new()
	version.needs_update = true
	version.sys_deploy_id = 11
	version.master_hash = "mh"
	version.tables = [
		MasterTable.new("mst_unit", "hu", "/x", 1),
		MasterTable.new("mst_gacha", "hg", "/x", 1),
		MasterTable.new("mst_equipment", "he", "/x", 1),
	]
	return version


## version の全テーブルのファイルを保存する（中身は行入りのテスト DB のコピー）。
func _save_all_tables(repository: LocalMasterDataRepository, version: MasterVersion) -> void:
	var bytes := FileAccess.get_file_as_bytes(_bundled_path)
	for table in version.tables:
		var saved := repository.save_table_file(table.name, table.hash, bytes)
		assert_bool(saved).is_true()


func _remove_dir(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for file_name in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file_name))
	for dir_name in DirAccess.get_directories_at(absolute):
		_remove_dir(path.path_join(dir_name))
	DirAccess.remove_absolute(absolute)
