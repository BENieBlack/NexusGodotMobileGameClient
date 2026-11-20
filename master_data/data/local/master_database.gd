## マスターの SQLite 接続を持つ（同梱 DB と更新 DB の切り替え。client_design.md 5 節）。
##
## 目的: 「今どの DB を読んでいるか」の 1 か所の持ち主。mst Repository はここ経由で読み、
##       DB が切り替わっても Repository を作り直さずに済む。
## 2 つの状態:
##   同梱 DB      res://data/master.db。1 つのファイルに全テーブルが入っている（アプリに同梱）
##   更新 DB      サーバーから取得した、テーブルごと（mst_unit など）の SQLite ファイル
## 使い方:
##   - open_bundled(path)  : 同梱 DB を開く（起動時の既定。更新 DB が使えないときの戻り先でもある）
##   - open_downloaded(map): 更新 DB（テーブル名 → ファイルのパス）を開く。必須テーブルが揃わなければ
##                           何も変えずに false を返す（旧 DB を維持）
##   - select_rows(table, sql, bindings): そのテーブルの DB に問い合わせる（失敗は空配列）
##   - try_select_rows(table, sql, bindings): 同じ問い合わせで、失敗と 0 件を区別して返す
## 失敗の扱い: 開けなければ false。問い合わせは DB が無い・エラーなら空配列。例外にしない。
## Godot の落とし穴: SQLite は GDExtension のクラスで、プラグインが無効な環境では存在しない。
##   ClassDB.class_exists("SQLite") で確かめてから使う。
class_name MasterDatabase
extends RefCounted

## 同期が成立するのに必要なテーブル。更新 DB にこれらが揃わないときは使わず、同梱 DB に戻す
## （旧 master_data_manager.gd の「必須グループ」と同じ。足りないまま切り替えると画面が空になるため）
const REQUIRED_TABLES: Array[String] = ["mst_gacha", "mst_unit", "mst_equipment"]

## 今使っている DB（テーブル名 → SQLite）。同梱 DB のときは全テーブルが同じ SQLite を指す
var _databases: Dictionary = {}
## 開いている SQLite の実体（閉じる対象。同じものを重複して持たない）
var _opened: Array = []
var _is_bundled: bool = false


## 同梱 DB を開く。成功したら現在の DB を同梱 DB に切り替える。
func open_bundled(path: String) -> bool:
	if not ClassDB.class_exists("SQLite"):
		push_error("SQLite プラグインが利用できません")
		return false
	var database: Object = ClassDB.instantiate("SQLite")
	database.path = path
	if not database.open_db():
		# 開けなかった接続も閉じる（open_downloaded と揃える。ハンドルを残さない）
		database.close_db()
		push_error("同梱 SQLite を開けません: " + path)
		return false
	close_all()
	_opened = [database]
	for table_name in REQUIRED_TABLES:
		_databases[table_name] = database
	_is_bundled = true
	return true


## 更新 DB を開く。table_files は {テーブル名: ファイルのパス}。
## 必須テーブルが 1 つでも欠ける・開けないときは、現在の DB を変えずに false を返す。
func open_downloaded(table_files: Dictionary) -> bool:
	if not ClassDB.class_exists("SQLite"):
		return false
	for table_name in REQUIRED_TABLES:
		if not table_files.has(table_name):
			return false

	# 新しい接続を全部開けてから、現在の DB と入れ替える（途中で失敗したら旧 DB のまま）
	var opened: Array = []
	var databases: Dictionary = {}
	for table_name: String in table_files:
		var database: Object = ClassDB.instantiate("SQLite")
		database.path = str(table_files[table_name])
		if not database.open_db():
			for opened_database in opened:
				opened_database.close_db()
			return false
		opened.append(database)
		databases[table_name] = database

	close_all()
	_opened = opened
	_databases = databases
	_is_bundled = false
	return true


## 同梱 DB を使っているか（更新 DB に切り替わっていなければ true）。
func is_bundled() -> bool:
	return _is_bundled


## DB を 1 つでも開いているか。
func is_open() -> bool:
	return not _databases.is_empty()


## table_name のテーブルを持つ DB に問い合わせ、行（Dictionary の配列）を返す。
## DB が無い・エラーのときは空配列。bindings は SQL の ? に入れる値。
func select_rows(table_name: String, sql: String, bindings: Array = []) -> Array:
	var database: Object = _databases.get(table_name, null)
	if database == null:
		return []
	if not database.query_with_bindings(sql, bindings):
		return []
	return database.query_result


## select_rows と同じ問い合わせを、失敗と 0 件を区別して返す（MasterRowsResult）。
## DB が開けていない・クエリが失敗（列なし・テーブルなし）なら ok = false、成功なら ok = true と行
## （0 件も成功）。既存の select_rows は変えない（失敗を空配列にする今の契約に他が依存している）。
## 使い道: 古い配信ファイルで新しい列（sort_desc など）が無いとき、空配列ではなく「読めない」と分かる。
func try_select_rows(table_name: String, sql: String, bindings: Array = []) -> MasterRowsResult:
	var database: Object = _databases.get(table_name, null)
	if database == null:
		return MasterRowsResult.new(false)
	if not database.query_with_bindings(sql, bindings):
		return MasterRowsResult.new(false)
	# query_result は次の問い合わせで書き換わりうるので、複製して渡す
	return MasterRowsResult.new(true, (database.query_result as Array).duplicate())


## すべての接続を閉じる。アプリ終了時と、DB の切り替えのときに呼ぶ。
func close_all() -> void:
	for database in _opened:
		database.close_db()
	_opened = []
	_databases = {}
	_is_bundled = false
