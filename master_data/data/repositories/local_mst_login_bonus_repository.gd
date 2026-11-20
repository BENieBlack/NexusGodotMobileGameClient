## 通常のログインボーナスのマスターを SQLite から読む（MstLoginBonusRepository の実装）。
##
## 流れ（find_by_id）:
##   1. mst_login_bonus（本体）を id で引く。問い合わせの失敗は UNREADABLE、0 件は NOT_FOUND
##   2. mst_login_bonus_content（報酬行）を別に引く。失敗は UNREADABLE（古い配信ファイルで sort_desc の
##      列が無いときもここに来る。select_rows だと空配列と見分けがつかないので try_select_rows を使う）
## 本体と報酬行は「テーブルごとに別の SQLite ファイル」なので JOIN できず、2 回に分ける
## （mst_item と mst_item__l10n のように同じファイルの親子ではない）。
## 並び: ORDER BY day, sort_desc DESC, content_type, content_mst_id（大きい sort_desc が先。同値は種別・ID の昇順）。
## 列は SELECT に明示する（配信ファイルに無い列を読まない）。キャッシュは持たない。
## 日の範囲外の行を捨てる・欠けた日を補う処理は、使う側（login の LoginBonusStageMasterReader）が行う。
class_name LocalMstLoginBonusRepository
extends MstLoginBonusRepository

const TABLE := "mst_login_bonus"
const CONTENT_TABLE := "mst_login_bonus_content"
const COLUMNS := "deploy_key, id, loop_days"
const CONTENT_COLUMNS := (
	"deploy_key, mst_login_bonus_id, day, content_type, content_mst_id, content_option, "
	+ "content_quantity, amount, is_paid, sort_desc"
)

var _database: MasterDatabase


func _init(database: MasterDatabase) -> void:
	_database = database


func find_by_id(id: String) -> MstLoginBonusLookup:
	# --- 1. 本体 ---
	var sql := "SELECT %s FROM %s WHERE id = ? LIMIT 1" % [COLUMNS, TABLE]
	var body := _database.try_select_rows(TABLE, sql, [id])
	if not body.ok:
		return MstLoginBonusLookup.new(MstLookupStatus.Status.UNREADABLE)
	if body.rows.is_empty():
		return MstLoginBonusLookup.new(MstLookupStatus.Status.NOT_FOUND)
	var row: Dictionary = body.rows[0]
	var bonus := MstLoginBonus.new()
	bonus.deploy_key = MstRowReader.get_int(row, "deploy_key")
	bonus.id = MstRowReader.get_string(row, "id")
	bonus.loop_days = MstRowReader.get_int(row, "loop_days")

	# --- 2. 報酬行（別の SQLite ファイル）---
	var content_sql := (
		(
			"SELECT %s FROM %s WHERE mst_login_bonus_id = ? "
			+ "ORDER BY day, sort_desc DESC, content_type, content_mst_id"
		)
		% [CONTENT_COLUMNS, CONTENT_TABLE]
	)
	var contents := _database.try_select_rows(CONTENT_TABLE, content_sql, [id])
	if not contents.ok:
		return MstLoginBonusLookup.new(MstLookupStatus.Status.UNREADABLE)
	for raw in contents.rows:
		bonus.contents.append(_row_to_content(raw))
	return MstLoginBonusLookup.new(MstLookupStatus.Status.FOUND, bonus)


## 報酬行 1 件を読み取りモデルに直す。NULL は既定値、content_option は JSON 文字列を辞書にする。
func _row_to_content(row: Dictionary) -> MstLoginBonusContent:
	var content := MstLoginBonusContent.new()
	content.deploy_key = MstRowReader.get_int(row, "deploy_key")
	content.mst_login_bonus_id = MstRowReader.get_string(row, "mst_login_bonus_id")
	content.day = MstRowReader.get_int(row, "day")
	content.content_type = MstRowReader.get_string(row, "content_type")
	content.content_mst_id = MstRowReader.get_string(row, "content_mst_id")
	content.content_option = MstRowReader.get_json_dict(row, "content_option")
	content.content_quantity = MstRowReader.get_int(row, "content_quantity")
	content.amount = MstRowReader.get_int(row, "amount")
	content.is_paid = MstRowReader.get_bool(row, "is_paid")
	content.sort_desc = MstRowReader.get_int(row, "sort_desc")
	return content
