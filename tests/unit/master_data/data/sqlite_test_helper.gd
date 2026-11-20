## SQLite を使うテスト用の補助。マスターの SQLite ファイルを、行入りで作る。
##
## 目的: 同梱 DB（data/master.db）は行が空なので、Repository の読み取りを検証するために、
##       テスト内で mst_unit / mst_equipment / mst_gacha の最小のファイルを作る。
## 注意: 書き込み先は user:// の下のテスト専用ディレクトリ（呼び出し側が後始末する）。
class_name SqliteTestHelper
extends RefCounted


## path に SQLite ファイルを作り、3 テーブルと数行を入れる。作れたら true。
static func create_master_db(path: String) -> bool:
	if not ClassDB.class_exists("SQLite"):
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var database: Object = ClassDB.instantiate("SQLite")
	database.path = path
	if not database.open_db():
		return false
	# 列は Repository が SELECT する列と同じ（実際の同梱 DB のスキーマと同じ並び）
	var unit_columns := "deploy_key INTEGER, id TEXT PRIMARY KEY, type TEXT, element TEXT, rarity TEXT"
	var equipment_columns := (
		"deploy_key INTEGER, id TEXT PRIMARY KEY, type TEXT, element TEXT, rarity TEXT, "
		+ "attack INTEGER, defense INTEGER, hp INTEGER, sort_desc INTEGER, is_active INTEGER"
	)
	var gacha_columns := (
		"deploy_key INTEGER, id TEXT PRIMARY KEY, sort_desc INTEGER, is_active INTEGER, "
		+ "start_at TEXT, end_at TEXT, daily_limit INTEGER, has_step_up INTEGER"
	)
	var statements := [
		"CREATE TABLE mst_unit (%s)" % unit_columns,
		"INSERT INTO mst_unit VALUES (1, 'u1', 'Attack', 'Fire', 'R')",
		"INSERT INTO mst_unit VALUES (1, 'u2', 'Support', 'Water', 'SSR')",
		"INSERT INTO mst_unit VALUES (1, 'u3', 'Defense', 'Wind', 'C')",
		"CREATE TABLE mst_equipment (%s)" % equipment_columns,
		"INSERT INTO mst_equipment VALUES (1, 'e1', 'Attack', 'Fire', 'R', 10, 5, 100, 2, 1)",
		"INSERT INTO mst_equipment VALUES (1, 'e2', 'Attack', 'Fire', 'R', 1, 1, 1, 1, 0)",
		"CREATE TABLE mst_gacha (%s)" % gacha_columns,
		"INSERT INTO mst_gacha VALUES (1, 'g1', 1, 1, NULL, NULL, 3, 1)",
	]
	for statement: String in statements:
		if not database.query(statement):
			database.close_db()
			return false
	database.close_db()
	return true


## path に SQLite ファイルを作り、mst_player_level と mst_config を入れる（配信から取り込まれる想定の
## 任意テーブル。同梱 DB にも REQUIRED_TABLES にも無いので、create_master_db とは別ファイルにする）。
static func create_home_master_db(path: String) -> bool:
	if not ClassDB.class_exists("SQLite"):
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var database: Object = ClassDB.instantiate("SQLite")
	database.path = path
	if not database.open_db():
		return false
	var statements := [
		(
			"CREATE TABLE mst_player_level (deploy_key INTEGER, level INTEGER PRIMARY KEY, "
			+ "required_exp INTEGER, max_stamina INTEGER)"
		),
		"INSERT INTO mst_player_level VALUES (1, 1, 0, 50)",
		"INSERT INTO mst_player_level VALUES (1, 2, 100, 52)",
		"INSERT INTO mst_player_level VALUES (1, 3, NULL, NULL)",
		(
			"CREATE TABLE mst_config (deploy_key INTEGER, id TEXT PRIMARY KEY, "
			+ "value TEXT, value_type TEXT)"
		),
		"INSERT INTO mst_config VALUES (1, 'stamina_recovery_interval_seconds', '300', 'int')",
		"INSERT INTO mst_config VALUES (1, 'float_value', '1.5', 'float')",
		"INSERT INTO mst_config VALUES (1, 'broken_int', 'abc', 'int')",
		"INSERT INTO mst_config VALUES (1, 'null_value', NULL, NULL)",
		"INSERT INTO mst_config VALUES (1, 'zero', '0', 'int')",
	]
	for statement: String in statements:
		if not database.query(statement):
			database.close_db()
			return false
	database.close_db()
	return true


## path に SQLite ファイルを作り、mst_item と mst_item__l10n を入れる（配信から取り込まれる想定の任意テーブル。
## 実際の配信と同じく l10n は親と同じファイルに入る）。
## 行: free_diamond（ja・en の名前）、en_only（en の名前だけ）、null_name（ja の name が NULL）、
##     no_l10n（l10n の行なし）、null_cols（deploy_key・type が NULL）。
static func create_item_master_db(path: String) -> bool:
	if not ClassDB.class_exists("SQLite"):
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var database: Object = ClassDB.instantiate("SQLite")
	database.path = path
	if not database.open_db():
		return false
	var statements := [
		"CREATE TABLE mst_item (deploy_key INTEGER, id TEXT PRIMARY KEY, type TEXT)",
		"INSERT INTO mst_item VALUES (1, 'free_diamond', 'currency')",
		"INSERT INTO mst_item VALUES (1, 'en_only', 'currency')",
		"INSERT INTO mst_item VALUES (1, 'null_name', 'currency')",
		"INSERT INTO mst_item VALUES (1, 'no_l10n', 'currency')",
		"INSERT INTO mst_item VALUES (NULL, 'null_cols', NULL)",
		(
			"CREATE TABLE mst_item__l10n (deploy_key INTEGER, mst_item_id TEXT, language TEXT, "
			+ "name TEXT, description TEXT, PRIMARY KEY (mst_item_id, language))"
		),
		"INSERT INTO mst_item__l10n VALUES (1, 'free_diamond', 'ja', '無償ダイヤ', NULL)",
		"INSERT INTO mst_item__l10n VALUES (1, 'free_diamond', 'en', 'Free Diamond', NULL)",
		"INSERT INTO mst_item__l10n VALUES (1, 'en_only', 'en', 'Only English', NULL)",
		"INSERT INTO mst_item__l10n VALUES (1, 'null_name', 'ja', NULL, NULL)",
	]
	for statement: String in statements:
		if not database.query(statement):
			database.close_db()
			return false
	database.close_db()
	return true


## path に SQLite ファイルを作り、statements（CREATE・INSERT）を順に実行する汎用の入口。作れたら true。
## ログインボーナスのように「テーブルごとに別のファイル」「列の有無を変えた版」を作るテストが使う。
static func create_db(path: String, statements: Array) -> bool:
	if not ClassDB.class_exists("SQLite"):
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var database: Object = ClassDB.instantiate("SQLite")
	database.path = path
	if not database.open_db():
		return false
	for statement: String in statements:
		if not database.query(statement):
			database.close_db()
			return false
	database.close_db()
	return true
