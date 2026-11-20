## 各 API 応答の updated_resources を、ホームが読む所持データの保持へ取り込む UseCase（client_design.md 3-3）。
##
## 目的: login 以外の応答（ログインボーナスの再受け取りなど）が返す「変更のあった所持データ」を、他コンテキストが
##       player の中身（entities・Repository）を知らずに、公開 UseCase だけで反映できるようにする
##       （architecture.md 2 節 他コンテキスト）。
## 取り込む範囲（ホームが読む 4 種だけ。ほかのキーは無視する）:
##   trx_item_list    行の mst_item_id を主キーに差し替え（無ければ追加。変更のあった行だけが載りうるので全置き換えにしない）
##   trx_wallet_list  行の mst_item_id を主キーに差し替え（無ければ追加。コインはここから読む）
##   trx_stamina_list 行の type を主キーに差し替え（無ければ追加）
##   trx_diamond      単数の辞書。キーがあり非空なら置き換える
##   trx_unit_list・trx_equipment_list は今のホームが読まないので取り込まない
## 入力の扱い: キー無し・null・型違い（配列のはずが辞書など）・主キーの無い行は無視して、何も壊さない。
## 削除行（is_delete）: 差し替えの行をそのまま入れ、表示側（CoinAmount など）の既存の除外に任せる。
## 保持の更新: current() の trx_lists を直接書き換えず、新しい PlayerState を作って replace() する（全量置き換えの契約）。
## サーバー時刻のオフセットは更新しない（login のときだけ）。
## 失敗の扱い: 失敗しない（メモリのみ）。他の UseCase と形をそろえて Result を返す。
class_name ApplyUpdatedResourcesUseCase
extends RefCounted

## 一覧のキー → 行の主キーの列名
const LIST_PRIMARY_KEYS := {
	"trx_item_list": "mst_item_id",
	"trx_wallet_list": "mst_item_id",
	"trx_stamina_list": "type",
}

var _player_repository: PlayerRepository


func _init(player_repository: PlayerRepository) -> void:
	_player_repository = player_repository


func handle(updated_resources: Dictionary) -> Result:
	var current := _player_repository.current()
	# --- 1. 一覧 3 種を主キーで差し替える（元の配列は書き換えず、新しい辞書・配列を作る）---
	var trx_lists: Dictionary = current.trx_lists.duplicate()
	for list_key: String in LIST_PRIMARY_KEYS:
		var rows: Variant = updated_resources.get(list_key, null)
		if not (rows is Array) or (rows as Array).is_empty():
			continue
		trx_lists[list_key] = _merge_rows(
			current.trx_list(list_key), rows, LIST_PRIMARY_KEYS[list_key]
		)

	# --- 2. 有償ダイヤ（単数）。非空の辞書だけ置き換える ---
	var trx_diamond: Dictionary = current.trx_diamond
	var diamond: Variant = updated_resources.get("trx_diamond", null)
	if diamond is Dictionary and not (diamond as Dictionary).is_empty():
		trx_diamond = diamond

	# --- 3. 新しい PlayerState で置き換える（サーバー時刻の情報は引き継ぐ）---
	_player_repository.replace(
		PlayerState.new(
			current.sys_player,
			trx_lists,
			trx_diamond,
			current.server_time_offset_seconds,
			current.has_server_time
		)
	)
	return Result.success()


## existing に incoming の行を、primary_key の値で差し替える（無ければ末尾に追加。他の行は残す）。
## 辞書でない行・primary_key が無い（空）行は無視する。
static func _merge_rows(existing: Array, incoming: Array, primary_key: String) -> Array:
	var merged: Array = existing.duplicate()
	for row in incoming:
		if not (row is Dictionary):
			continue
		var key := str(row.get(primary_key, ""))
		if key == "":
			continue
		var index := _index_of(merged, primary_key, key)
		if index >= 0:
			merged[index] = row
		else:
			merged.append(row)
	return merged


static func _index_of(rows: Array, primary_key: String, key: String) -> int:
	for i in range(rows.size()):
		var row: Variant = rows[i]
		if row is Dictionary and str(row.get(primary_key, "")) == key:
			return i
	return -1
