## CheckMasterDataUseCase のテスト用の偽 Repository 2 種（remote と storage）。
##
## 目的: ネットワーク・ファイル・SQLite なしで、同期 UseCase の分岐だけを検証する。
## 使い方: FakeMasterRepositories.FakeRemote / FakeStorage を new して UseCase に渡し、
##   呼ばれた記録（downloaded / saved / committed）を検証する。
class_name FakeMasterRepositories
extends RefCounted


## 偽のサーバー側。version と、テーブルごとのダウンロード結果を設定できる。
class FakeRemote:
	extends MasterDataRemoteRepository
	## fetch_version の結果（null なら ok で version を返す）
	var version: MasterVersion = null
	var version_error: AppError = null
	## download_table を失敗させるテーブル名
	var failing_tables: Array[String] = []
	## 実際に取得を要求されたテーブル名（順）
	var downloaded: Array[String] = []
	var fetch_count: int = 0
	## fetch_version を待たせる（同時実行の再現用）。true の間は 1 フレームずつ待つ
	var delay_frames: int = 0

	func fetch_version(_deploy_id: int) -> MasterVersionResult:
		fetch_count += 1
		for i in range(delay_frames):
			await Engine.get_main_loop().process_frame
		if version_error != null:
			return MasterVersionResult.new(null, version_error)
		return MasterVersionResult.new(version)

	func download_table(table: MasterTable) -> MasterTableFileResult:
		downloaded.append(table.name)
		if failing_tables.has(table.name):
			return MasterTableFileResult.new(PackedByteArray(), AppError.new(AppError.Kind.NETWORK))
		return MasterTableFileResult.new(PackedByteArray([1]))


## 偽の端末側の保存。メモリだけで、保存・確定の記録を持つ。
class FakeStorage:
	extends MasterStorageRepository
	var deploy: int = 5
	var hash_value: String = ""
	var hashes: Dictionary = {}
	## ファイルが端末に無いことにするテーブル名（has_table_file が false を返す）
	var missing_files: Array[String] = []
	## save_table_file を失敗させるか
	var save_fails: bool = false
	## commit_update の戻り値
	var commit_result: bool = true
	var saved: Array[String] = []
	var commit_count: int = 0

	func deploy_id() -> int:
		return deploy

	func master_hash() -> String:
		return hash_value

	func table_hashes() -> Dictionary:
		return hashes

	func has_table_file(table_name: String, _hash: String) -> bool:
		return not missing_files.has(table_name)

	func save_table_file(table_name: String, _hash: String, _bytes: PackedByteArray) -> bool:
		if save_fails:
			return false
		saved.append(table_name)
		return true

	func commit_update(version: MasterVersion) -> bool:
		commit_count += 1
		if commit_result:
			deploy = version.sys_deploy_id
		return commit_result


## テスト用の MasterVersion を作る。tables は {テーブル名: ハッシュ} から作る。
static func make_version(
	needs_update: bool, table_hashes: Dictionary = {}, deploy_id: int = 9
) -> MasterVersion:
	var version := MasterVersion.new()
	version.needs_update = needs_update
	version.sys_deploy_id = deploy_id
	version.master_hash = "master-hash"
	for table_name: String in table_hashes:
		var table_hash: String = table_hashes[table_name]
		version.tables.append(
			MasterTable.new(
				table_name, table_hash, "/masterdata/%s/%s.sqlite" % [table_hash, table_name], 1
			)
		)
	return version
