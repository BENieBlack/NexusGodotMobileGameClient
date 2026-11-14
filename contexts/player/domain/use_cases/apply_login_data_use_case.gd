## login の結果のうち、プレイヤーと所持データを player の保持先に反映する UseCase（client_design.md 2-1・4 節）。
##
## 目的: 他コンテキスト（login）が player の中身（entities・Repository）を知らずに、公開 UseCase だけで
##       プレイヤー・所持データを渡せるようにする（architecture.md 2 節 他コンテキスト）。
## 入力: sys_player（辞書）、trx_lists（PlayerState.TRX_LIST_KEYS のキーの辞書。値は Array）、
##   trx_diamond（有償ダイヤの単数の辞書。無ければ {}）、サーバー時刻のオフセット（秒）と、その有効フラグ。
##   型は辞書のまま渡す。login の data/api が null と欠落を既に処理した値（D3）なので、ここでは再度処理しない。
##   ただし 5 種のどれかのキーが欠けていても落ちないよう、無いキーは空配列で補う。
## 失敗の扱い: 失敗しない（メモリに置くだけ）。他の UseCase と形をそろえて Result を返す。
class_name ApplyLoginDataUseCase
extends RefCounted

var _player_repository: PlayerRepository


func _init(player_repository: PlayerRepository) -> void:
	_player_repository = player_repository


func handle(
	sys_player: Dictionary,
	trx_lists: Dictionary,
	trx_diamond: Dictionary = {},
	server_time_offset_seconds: int = 0,
	has_server_time: bool = false
) -> Result:
	# 5 種すべてのキーを持つ辞書にそろえる（読む側が「キーが無い」を気にしなくてよいように）
	var complete: Dictionary = {}
	for key in PlayerState.TRX_LIST_KEYS:
		var value: Variant = trx_lists.get(key, [])
		complete[key] = value if value is Array else []
	_player_repository.replace(
		PlayerState.new(
			sys_player, complete, trx_diamond, server_time_offset_seconds, has_server_time
		)
	)
	return Result.success()
