## ログイン済みのプレイヤー ID（sys_player.my_id）を返す UseCase。
##
## 目的: ホーム画面の表示と、リアルタイム通知のチャンネル名（private-notification.<id>）に使う。
##       presenter が Repository を直接触らないための窓口。
## 戻り値: プレイヤー ID の文字列。login 前・セッション破棄後は空文字。
class_name GetPlayerIdUseCase
extends RefCounted

var _player_repository: PlayerRepository


func _init(player_repository: PlayerRepository) -> void:
	_player_repository = player_repository


## プレイヤー ID を返す（未ログインなら空文字）。
func handle() -> String:
	return _player_repository.current().user_id()
