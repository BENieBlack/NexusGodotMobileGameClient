## スタミナの表示値を now 時点で求める UseCase（client_design.md 2-2・3-3）。
##
## 目的: tick（1 秒）と復帰のたびに、起点（StaminaSource）から現在の表示値を計算する。
## now = 端末の時刻（Clock）+ login 時に作ったサーバー時刻のオフセット。端末の時計がずれていても、
##       ログイン時点のサーバー時刻に合わせる（Date が読めなかったときのオフセットは 0 = 端末時計のまま）。
## 計算は StaminaRecovery に任せる。保持データ・起点は書き換えない（二重加算なし）。
class_name GetStaminaDisplayUseCase
extends RefCounted

var _player_repository: PlayerRepository
var _clock: Clock


func _init(player_repository: PlayerRepository, clock: Clock) -> void:
	_player_repository = player_repository
	_clock = clock


func handle(source: StaminaSource) -> StaminaDisplay:
	var offset := _player_repository.current().server_time_offset_seconds
	return StaminaRecovery.calculate(source, _clock.now_unix() + offset)
