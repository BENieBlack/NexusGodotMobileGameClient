## マスターの端末側の保存（MasterStorageRepository の実装）。ハッシュ管理・ファイル保存・DB の切り替え。
##
## 目的: 同期 UseCase が呼ぶ保存の窓口。端末のマスターの状態（deploy_id・master_hash・テーブルごとのハッシュ）
##       の持ち主はここ 1 か所（旧 UserDataManager.master_hash / master_deploy_id と
##       master_data_manager.gd のハッシュ保存を移した。アカウントに依存しないので、
##       session_expired でも消さない）。
## 保存する場所:
##   user://master/{テーブル名}_{ハッシュ}.sqlite  ダウンロードした SQLite（ハッシュ入りの名前で新旧が混ざらない）
##   user://master_state.json                        {"deploy_id": int, "master_hash": String,
##                                                    "table_hashes": {テーブル名: ハッシュ}}
## 流れ:
##   1. initialize() : 起動時。保存済みの更新 DB が使えればそれを、無ければ同梱 DB を開く
##      （旧実装は起動のたびに同梱 DB から始まり、更新が無い起動では更新 DB を使えなかった。
##       端末に更新 DB があるのに同梱へ戻る食い違いを避ける）。ファイルが欠けていたら deploy_id と
##      master_hash を空に戻し、次の version 確認で（サーバーに needs_update と言わせて）取り直す
##   2. save_table_file() : 差分のテーブルを 1 つずつ保存する（まだ切り替えない）
##   3. commit_update() : 全部保存し終えたら更新 DB に切り替え、成功したらハッシュ・deploy_id を保存し、
##      現行のハッシュに無い古いファイルを消す。必須テーブルが揃わなければ同梱 DB へ戻し、保存は更新しない
## ファイルの書き込みは、一時ファイル（.tmp）に書いてから rename で確定する（書きかけのファイルが
## 本物の名前で残ると、次回起動で壊れた SQLite を開いてしまうため）。
## テスト: 保存先と同梱 DB のパスは引数で変えられる（実機の user:// を汚さない）。
class_name LocalMasterDataRepository
extends MasterStorageRepository

const DEFAULT_MASTER_DIR := "user://master/"
const DEFAULT_STATE_PATH := "user://master_state.json"
const DEFAULT_BUNDLED_PATH := "res://data/master.db"

var _database: MasterDatabase
var _master_dir: String
var _state_path: String
var _bundled_path: String

## 保存の中身（上の master_state.json と同じ形）
var _deploy_id: int = 0
var _master_hash: String = ""
var _table_hashes: Dictionary = {}


func _init(
	database: MasterDatabase,
	master_dir: String = DEFAULT_MASTER_DIR,
	state_path: String = DEFAULT_STATE_PATH,
	bundled_path: String = DEFAULT_BUNDLED_PATH
) -> void:
	_database = database
	_master_dir = master_dir if master_dir.ends_with("/") else master_dir + "/"
	_state_path = state_path
	_bundled_path = bundled_path
	_load_state()


## 起動時に使う DB を開く。更新 DB が使えればそれ、無ければ同梱 DB。何かの DB が開けたら true。
func initialize() -> bool:
	if not _table_hashes.is_empty():
		var files := _table_files(_table_hashes)
		# 保存の全テーブルのファイルがそろっていなければ、状態を「未取得」に戻す。deploy_id が
		# サーバーの最新と同じままだと needs_update が偽になり、欠けたファイルを永遠に取り直せないため。
		# table_hashes は残す（ファイルがある分は差分判定でそのまま使える）
		if files.size() != _table_hashes.size():
			_deploy_id = 0
			_master_hash = ""
			_save_state()
		# 必須テーブルが無い・開けない場合は open_downloaded が false を返す（旧 DB は触らない）
		if not files.is_empty() and _database.open_downloaded(files):
			return true
	return _database.open_bundled(_bundled_path)


func deploy_id() -> int:
	return _deploy_id


func master_hash() -> String:
	return _master_hash


func table_hashes() -> Dictionary:
	return _table_hashes.duplicate()


func has_table_file(table_name: String, hash: String) -> bool:
	return FileAccess.file_exists(_table_file_path(table_name, hash))


## テーブルのファイルを保存する。ディレクトリが無ければ作る。書き込みに失敗したら false。
func save_table_file(table_name: String, hash: String, bytes: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(_master_dir)
	return _write_atomically(_table_file_path(table_name, hash), bytes)


## 更新を確定する。version.tables のファイルを開いて DB を切り替え、成功したら保存を更新する。
## 失敗（必須テーブルが揃わない・開けない）のときは同梱 DB に戻して false。保存は更新しない。
func commit_update(version: MasterVersion) -> bool:
	var new_hashes: Dictionary = {}
	for table in version.tables:
		new_hashes[table.name] = table.hash

	var files := _table_files(new_hashes)
	if not _database.open_downloaded(files):
		# 切り替えに失敗。旧 DB（更新 DB かもしれない）が開いたままなので、確実に動く同梱 DB へ戻す
		_database.open_bundled(_bundled_path)
		return false

	# 切り替えに成功してから保存する（失敗時に「保存だけ新しい」状態を作らず、再試行できるようにする）
	_table_hashes = new_hashes
	_master_hash = version.master_hash
	_deploy_id = version.sys_deploy_id
	# 状態の保存に失敗しても、今回の起動は新しい DB で動く。次回起動は古い状態（または状態なし）を読み、
	# 古いファイルが残っていればそれを開いて、次の version 確認で取り直す（状態なしなら全取得し直す）。
	# そのため、保存に失敗したときは古いファイルを消さない（消すと次回に開ける DB が無くなる）
	if _save_state():
		_remove_stale_files(files)
	return true


## 現行のファイル以外の古いテーブルファイル（旧ハッシュのもの・書きかけの .tmp）を消す。
## keep は現行の {テーブル名: パス}。端末の容量を、更新のたびに増やさないため。
func _remove_stale_files(keep: Dictionary) -> void:
	var keep_names: Array[String] = []
	for path: String in keep.values():
		keep_names.append(path.get_file())
	var absolute_dir := ProjectSettings.globalize_path(_master_dir)
	for file_name in DirAccess.get_files_at(absolute_dir):
		if file_name.ends_with(".sqlite") or file_name.ends_with(".tmp"):
			if not keep_names.has(file_name):
				DirAccess.remove_absolute(absolute_dir.path_join(file_name))


## {テーブル名: ハッシュ} から、実在するファイルだけの {テーブル名: パス} を作る。
func _table_files(hashes: Dictionary) -> Dictionary:
	var files: Dictionary = {}
	for table_name: String in hashes:
		var path := _table_file_path(table_name, str(hashes[table_name]))
		if FileAccess.file_exists(path):
			files[table_name] = path
	return files


func _table_file_path(table_name: String, hash: String) -> String:
	return "%s%s_%s.sqlite" % [_master_dir, table_name, hash]


## 状態ファイルを読む。無い・壊れているときは空の状態（初回扱い）にする。
func _load_state() -> void:
	if not FileAccess.file_exists(_state_path):
		return
	var file := FileAccess.open(_state_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	var state: Dictionary = parsed
	_deploy_id = int(state.get("deploy_id", 0))
	_master_hash = str(state.get("master_hash", ""))
	_table_hashes = JsonReader.get_dict(state, "table_hashes")


## 状態を保存する。成功したら true。
func _save_state() -> bool:
	var state := {
		"deploy_id": _deploy_id,
		"master_hash": _master_hash,
		"table_hashes": _table_hashes,
	}
	var ok := _write_atomically(_state_path, JSON.stringify(state).to_utf8_buffer())
	if not ok:
		push_warning("マスターの状態を保存できません: " + _state_path)
	return ok


## path に bytes を書く。一時ファイル（path + ".tmp"）に書き、書き込みの成否を確かめてから rename で確定する。
## 書き込み途中の失敗（容量不足など）で本物のファイルを壊さない。失敗したら一時ファイルを消して false。
func _write_atomically(path: String, bytes: PackedByteArray) -> bool:
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	var stored := file.store_buffer(bytes)
	# store_buffer の戻りと、バッファに残った書き込みエラーの両方を見る（close で flush されるため
	# close の後にも確かめる）
	file.close()
	var write_ok := stored and file.get_error() == OK
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	if write_ok:
		write_ok = (
			DirAccess.rename_absolute(absolute_temp, ProjectSettings.globalize_path(path)) == OK
		)
	if not write_ok:
		DirAccess.remove_absolute(absolute_temp)
	return write_ok
