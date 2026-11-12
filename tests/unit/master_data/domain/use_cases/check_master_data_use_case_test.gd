## CheckMasterDataUseCase の単体テスト（client_design.md 5 節）。
##
## 偽の Repository を差し替え、更新あり・なし・各種の失敗を検証する。
## 失敗時は「FAILED を返し、DB の切り替え（commit）をしない」＝端末は同梱（または前回取得済み）の
## DB のまま続行できる、ことを守る（D8）。
extends GdUnitTestSuite

var _remote: FakeMasterRepositories.FakeRemote
var _storage: FakeMasterRepositories.FakeStorage
var _use_case: CheckMasterDataUseCase


func before_test() -> void:
	_remote = FakeMasterRepositories.FakeRemote.new()
	_storage = FakeMasterRepositories.FakeStorage.new()
	_use_case = CheckMasterDataUseCase.new(_remote, _storage)


## 前提: サーバーが needs_update = false。操作: handle。
## 期待: UP_TO_DATE（ok）で、ダウンロードも切り替えもしない。
func test_up_to_date_does_nothing() -> void:
	_remote.version = FakeMasterRepositories.make_version(false)
	var result := await _use_case.handle()
	assert_bool(result.ok).is_true()
	assert_int(result.status).is_equal(CheckMasterDataResult.Status.UP_TO_DATE)
	assert_array(_remote.downloaded).is_empty()
	assert_int(_storage.commit_count).is_equal(0)


## 前提: 3 テーブルのうち 1 つだけハッシュが違う。操作: handle。
## 期待: 違う 1 つだけ取得・保存し、進捗は (1/1)、commit は 1 回、master_data_loaded が出て UPDATED。
## 差分だけ取ること（全件取りしない）と、全部そろってから 1 回だけ切り替えることを守る。
func test_update_downloads_only_changed_tables_and_commits_once() -> void:
	_storage.hashes = {"mst_unit": "u1", "mst_gacha": "g1", "mst_equipment": "e1"}
	_remote.version = FakeMasterRepositories.make_version(
		true, {"mst_unit": "u2", "mst_gacha": "g1", "mst_equipment": "e1"}
	)
	var progress: Array = []
	_use_case.download_progress.connect(func(c, t, n): progress.append([c, t, n]))
	var loaded := [0]
	_use_case.master_data_loaded.connect(func(): loaded[0] += 1)

	var result := await _use_case.handle()

	assert_bool(result.ok).is_true()
	assert_int(result.status).is_equal(CheckMasterDataResult.Status.UPDATED)
	assert_array(_remote.downloaded).contains_exactly(["mst_unit"])
	assert_array(_storage.saved).contains_exactly(["mst_unit"])
	assert_array(progress).contains_exactly([[1, 1, "mst_unit"]])
	assert_int(_storage.commit_count).is_equal(1)
	assert_int(loaded[0]).is_equal(1)
	assert_int(_storage.deploy).is_equal(9)


## 前提: 端末が空（初回）。操作: handle。期待: 全テーブルを取得し、進捗が (1/3)(2/3)(3/3)。
func test_first_update_downloads_all_tables_with_progress() -> void:
	_remote.version = FakeMasterRepositories.make_version(
		true, {"mst_unit": "u", "mst_gacha": "g", "mst_equipment": "e"}
	)
	var progress: Array = []
	_use_case.download_progress.connect(func(c, t, _n): progress.append([c, t]))
	var result := await _use_case.handle()
	assert_int(result.status).is_equal(CheckMasterDataResult.Status.UPDATED)
	assert_array(progress).contains_exactly([[1, 3], [2, 3], [3, 3]])


## 前提: version の通信が失敗（NETWORK）。操作: handle。
## 期待: FAILED（ok=false）で error の kind が NETWORK。切り替えない（同梱 DB のまま続行できる）。
func test_version_failure_returns_failed_without_commit() -> void:
	_remote.version_error = AppError.new(AppError.Kind.NETWORK)
	var result := await _use_case.handle()
	assert_bool(result.ok).is_false()
	assert_int(result.status).is_equal(CheckMasterDataResult.Status.FAILED)
	assert_int(result.error.kind).is_equal(AppError.Kind.NETWORK)
	assert_int(_storage.commit_count).is_equal(0)


## 前提: needs_update = true なのに master.tables が空。操作: handle。期待: FAILED（更新の中身が無いのは異常）。
func test_empty_tables_is_failed() -> void:
	_remote.version = FakeMasterRepositories.make_version(true, {})
	var result := await _use_case.handle()
	assert_int(result.status).is_equal(CheckMasterDataResult.Status.FAILED)
	assert_int(_storage.commit_count).is_equal(0)


## 前提: 2 つ目のテーブルのダウンロードが失敗。操作: handle。
## 期待: FAILED。commit しない（1 つ目だけ新しい状態で切り替えて新旧が混ざるのを防ぐ）。
func test_download_failure_returns_failed_without_commit() -> void:
	_remote.version = FakeMasterRepositories.make_version(
		true, {"mst_unit": "u", "mst_gacha": "g", "mst_equipment": "e"}
	)
	_remote.failing_tables = ["mst_gacha"]
	var result := await _use_case.handle()
	assert_int(result.status).is_equal(CheckMasterDataResult.Status.FAILED)
	assert_int(result.error.kind).is_equal(AppError.Kind.NETWORK)
	assert_int(_storage.commit_count).is_equal(0)
	assert_int(_storage.deploy).is_equal(5)


## 前提: ファイルの保存が失敗。操作: handle。期待: FAILED（LOCAL）。commit しない。
func test_save_failure_returns_failed() -> void:
	_remote.version = FakeMasterRepositories.make_version(true, {"mst_unit": "u"})
	_storage.save_fails = true
	var result := await _use_case.handle()
	assert_int(result.status).is_equal(CheckMasterDataResult.Status.FAILED)
	assert_int(result.error.kind).is_equal(AppError.Kind.LOCAL)
	assert_int(_storage.commit_count).is_equal(0)


## 前提: 取得は成功したが commit が false（必須テーブルが揃わず、Repository が同梱 DB へ戻した）。
## 操作: handle。期待: FAILED。master_data_loaded は出さない。
func test_commit_failure_is_failed_and_does_not_signal_loaded() -> void:
	_remote.version = FakeMasterRepositories.make_version(true, {"mst_unit": "u"})
	_storage.commit_result = false
	var loaded := [0]
	_use_case.master_data_loaded.connect(func(): loaded[0] += 1)
	var result := await _use_case.handle()
	assert_int(result.status).is_equal(CheckMasterDataResult.Status.FAILED)
	assert_int(loaded[0]).is_equal(0)


## 前提: 1 回目の handle の実行中（version 待ち）に 2 回目の handle が来る。
## 期待: 2 回目は IN_PROGRESS（UP_TO_DATE ではない。更新済みと誤認させない）を返し、
##   1 回目の終了後に version の確認が 1 回だけ再実行される（計 2 回）。
## 実行中に来た更新通知（X-Master-Update-Required）を取りこぼさず、かつ二重ダウンロードもしないため。
func test_concurrent_handle_returns_in_progress_and_reruns_once() -> void:
	_remote.version = FakeMasterRepositories.make_version(false)
	_remote.delay_frames = 3
	var results := {}
	_start(results, "first")
	await Engine.get_main_loop().process_frame
	assert_bool(_use_case.is_running()).is_true()
	var second := await _use_case.handle()
	assert_int(second.status).is_equal(CheckMasterDataResult.Status.IN_PROGRESS)
	var third := await _use_case.handle()
	assert_int(third.status).is_equal(CheckMasterDataResult.Status.IN_PROGRESS)
	for i in range(40):
		if results.has("first"):
			break
		await Engine.get_main_loop().process_frame
	# 2 回の呼び出しが重なっても、再実行は 1 回だけ（1 回目 + 再実行 1 回）
	assert_int(_remote.fetch_count).is_equal(2)
	assert_int(results["first"].status).is_equal(CheckMasterDataResult.Status.UP_TO_DATE)
	assert_bool(_use_case.is_running()).is_false()


## 前提: ハッシュは保存済みと同じだが、そのテーブルのファイルが端末に無い。操作: handle。
## 期待: ファイルが無いテーブルだけ取り直す（ハッシュだけの判定だと、消えたファイルを取り戻せない）。
func test_missing_file_is_downloaded_even_if_hash_matches() -> void:
	_storage.hashes = {"mst_unit": "u1", "mst_gacha": "g1"}
	_storage.missing_files = ["mst_gacha"]
	_remote.version = FakeMasterRepositories.make_version(
		true, {"mst_unit": "u1", "mst_gacha": "g1"}
	)
	var result := await _use_case.handle()
	assert_int(result.status).is_equal(CheckMasterDataResult.Status.UPDATED)
	assert_array(_remote.downloaded).contains_exactly(["mst_gacha"])


func _start(results: Dictionary, key: String) -> void:
	results[key] = await _use_case.handle()
