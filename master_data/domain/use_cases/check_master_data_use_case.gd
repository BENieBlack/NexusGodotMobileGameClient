## マスターデータの同期（バージョン確認 → 差分取得 → DB の切り替え）の UseCase（client_design.md 5 節）。
##
## 目的: タイトルの最初の段階（認証の前）と、起動後にサーバーが更新されたとき（X-Master-Update-Required。
##       AppContext が EventBus の master_update_required を受けて呼ぶ）に、端末のマスターを最新にする。
## 流れ（handle）:
##   1. 実行中なら IN_PROGRESS を返して何もしない（同時に 1 本だけ。二重ダウンロードを避ける）。
##      ただし実行中に来た呼び出しは「新しい更新通知」かもしれないので、実行中の同期が終わったあと
##      1 回だけ再実行する（通知が連続しても再実行は 1 回にまとまる）
##   2. version API を呼ぶ（保存済みの deploy_id を送る。認証不要）。失敗なら FAILED
##   3. needs_update が偽なら UP_TO_DATE
##   4. master.tables が空なら FAILED（更新の中身が無いのは異常）
##   5. 保存済みのハッシュと比べ、違うテーブルだけ 1 つずつダウンロードして保存する
##      （download_progress で進捗を知らせる。1 つでも失敗したら FAILED。旧 DB のまま）
##   6. 全テーブルの取得後に commit_update で DB を切り替える。必須グループが揃わなければ FAILED
##      （Repository が同梱 DB へ戻している）。成功したら master_data_loaded を出して UPDATED
## 失敗の扱い: 例外にせず FAILED の結果で返す。呼び出し元（タイトルの presenter）が、止めずに続行して通知する。
## 依存: Repository の契約（remote / storage）だけ。HTTP・ファイル・SQLite を知らない（テストは偽物を渡す）。
class_name CheckMasterDataUseCase
extends RefCounted

## 1 テーブルの取得を始めるとき。表示用（「マスターデータを更新中 (n/m)」）
signal download_progress(current: int, total: int, table_name: String)

## DB を切り替えて、新しいマスターを読めるようになったとき
signal master_data_loaded

var _remote: MasterDataRemoteRepository
var _storage: MasterStorageRepository
var _is_running: bool = false
## 実行中に呼び出しがあった（終了後に 1 回だけ再実行する）
var _rerun_requested: bool = false


func _init(remote: MasterDataRemoteRepository, storage: MasterStorageRepository) -> void:
	_remote = remote
	_storage = storage


## 同期を実行する。呼び出し側は await する。失敗でも例外にしない（FAILED の結果）。
func handle() -> CheckMasterDataResult:
	# --- 1. 同時実行を防ぐ ---
	# 更新の通知は応答のたびに届きうる。実行中の呼び出しは並行して走らせず（二重ダウンロードを避ける）、
	# IN_PROGRESS を返す。UP_TO_DATE を返すと呼び出し側が「更新済み」と誤認するため別の状態にする
	if _is_running:
		_rerun_requested = true
		return CheckMasterDataResult.new(CheckMasterDataResult.Status.IN_PROGRESS, "更新中です")
	_is_running = true
	var result := await _run()
	# 実行中に届いた通知は、実行中の version 確認より新しい更新を指すかもしれないので 1 回だけやり直す。
	# 再実行中に届いた通知は、再実行の version 確認が最新を見るので、フラグを捨てて繰り返さない
	if _rerun_requested:
		_rerun_requested = false
		result = await _run()
		_rerun_requested = false
	_is_running = false
	return result


## 実行中か。
func is_running() -> bool:
	return _is_running


func _run() -> CheckMasterDataResult:
	# --- 2. version を確認する ---
	var version_result := await _remote.fetch_version(_storage.deploy_id())
	if not version_result.ok:
		return _failed("version の取得に失敗しました", version_result.error)
	var version := version_result.version

	# --- 3. 更新の要否 ---
	if not version.needs_update:
		return CheckMasterDataResult.new(CheckMasterDataResult.Status.UP_TO_DATE)

	# --- 4. 更新の中身 ---
	if version.tables.is_empty():
		return _failed("master.tables が空です", AppError.new(AppError.Kind.PARSE))

	# --- 5. 差分のテーブルだけ取得して保存する ---
	var failure := await _download_changed_tables(version)
	if failure != null:
		return failure

	# --- 6. 全部そろってから DB を切り替える ---
	# 途中で失敗したときに新旧が混ざらないよう、切り替えとハッシュの保存は最後に 1 回だけ行う
	if not _storage.commit_update(version):
		return _failed("必須テーブルが揃わず、DB を切り替えられませんでした", AppError.new(AppError.Kind.LOCAL))
	master_data_loaded.emit()
	return CheckMasterDataResult.new(CheckMasterDataResult.Status.UPDATED)


## 保存済みのハッシュと違うテーブルだけを、1 つずつ取得して保存する（まだ切り替えない）。
## 戻り値: 全部成功なら null。1 つでも失敗したらその FAILED の結果（以降のテーブルは取らない）。
func _download_changed_tables(version: MasterVersion) -> CheckMasterDataResult:
	# 差分は「ハッシュが違う、またはファイルが無い」。ハッシュだけで見ると、ファイルが消えた端末で
	# 取り直せない（保存のハッシュは新しいままになる）
	var local_hashes := _storage.table_hashes()
	var changed: Array[MasterTable] = []
	for table in version.tables:
		var hash_differs := str(local_hashes.get(table.name, "")) != table.hash
		if hash_differs or not _storage.has_table_file(table.name, table.hash):
			changed.append(table)

	var current := 0
	for table in changed:
		current += 1
		download_progress.emit(current, changed.size(), table.name)
		var file_result := await _remote.download_table(table)
		if not file_result.ok:
			return _failed("%s のダウンロードに失敗しました" % table.name, file_result.error)
		if not _storage.save_table_file(table.name, table.hash, file_result.bytes):
			return _failed("%s を保存できませんでした" % table.name, AppError.new(AppError.Kind.LOCAL))
	return null


func _failed(message: String, error: AppError) -> CheckMasterDataResult:
	push_warning("マスターデータ更新失敗: " + message)
	return CheckMasterDataResult.new(CheckMasterDataResult.Status.FAILED, message, error)
