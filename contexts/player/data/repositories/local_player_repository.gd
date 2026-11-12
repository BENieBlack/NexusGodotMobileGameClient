## プレイヤーと所持データの保持先（PlayerRepository の実装。メモリのみ）。
##
## 目的: login で取った sys_player と trx 6 種をセッションの間だけ持つ。永続化しない
##       （旧 UserDataManager.save_user_data と同じ扱い。毎回 login で取り直すため）。
## 破棄: セッションが無効になったとき（EventBus.session_expired。AppContext が受け手として登録）に clear() で空にする。
class_name LocalPlayerRepository
extends PlayerRepository

var _state: PlayerState = PlayerState.new()


func replace(state: PlayerState) -> void:
	_state = state


func current() -> PlayerState:
	return _state


func clear() -> void:
	_state = PlayerState.new()
