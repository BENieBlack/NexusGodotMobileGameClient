## アイテムマスター（mst_item と mst_item__l10n）を SQLite から読む（MstItemRepository の実装）。
##
## 流れ:
##   1. mst_item から id の行を引く（無ければ null）
##   2. mst_item__l10n から、構築時に渡された言語の name を引く（無ければ name は空文字）
## mst_item は同梱 DB に無く、配信があるときだけ更新 DB に入る（必須テーブルにしない。MASTER_DATA.md）。
## 無いときは MasterDatabase.select_rows が空配列を返すので、null を返すだけ（例外にしない）。
## mst_item__l10n は mst_item と同じ SQLite ファイルに入る（配信の仕組み）ので、
## select_rows には親テーブル名（mst_item）をキーとして渡して両方に届かせる。
## 言語の連鎖（ja が無ければ en など）は作らない。無ければ使う側のフォールバックに任せる。キャッシュは持たない。
class_name LocalMstItemRepository
extends MstItemRepository

const TABLE := "mst_item"
const COLUMNS := "deploy_key, id, type"

var _database: MasterDatabase
## l10n の language 列と照合する値（ApiConfig.language() を AppContext が渡す）
var _language: String = ""


func _init(database: MasterDatabase, language: String) -> void:
	_database = database
	_language = language


func get_by_id(id: String) -> MstItem:
	# --- 1. mst_item の行 ---
	var sql := "SELECT %s FROM %s WHERE id = ? LIMIT 1" % [COLUMNS, TABLE]
	var rows := _database.select_rows(TABLE, sql, [id])
	if rows.is_empty():
		return null
	var model := _row_to_model(rows[0])
	# --- 2. l10n の名前（親と同じ SQLite ファイル。親名のキーで引く）---
	var l10n_sql := "SELECT name FROM mst_item__l10n WHERE mst_item_id = ? AND language = ? LIMIT 1"
	var l10n_rows := _database.select_rows(TABLE, l10n_sql, [id, _language])
	if not l10n_rows.is_empty():
		var raw_name: Variant = (l10n_rows[0] as Dictionary).get("name", null)
		model.name = "" if raw_name == null else str(raw_name)
	return model


## SQLite の 1 行（Dictionary）を読み取りモデルに直す。NULL は既定値（空文字・0）。
func _row_to_model(row: Dictionary) -> MstItem:
	var model := MstItem.new()
	var raw_key: Variant = row.get("deploy_key", null)
	model.deploy_key = 0 if raw_key == null else int(raw_key)
	var raw_id: Variant = row.get("id", null)
	model.id = "" if raw_id == null else str(raw_id)
	var raw_type: Variant = row.get("type", null)
	model.type = "" if raw_type == null else str(raw_type)
	return model
