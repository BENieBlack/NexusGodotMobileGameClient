## プレイヤーと所持データの保持先の契約（architecture.md 7 節）。
##
## 目的: ApplyLoginDataUseCase が保持の実装を知らずに、テストでは偽物に差し替えられるようにする。
## 実装: contexts/player/data/repositories/local_player_repository.gd（メモリのみ）。
## 状態の持ち主はこの Repository 1 つ（オートロードに状態を置かない。architecture.md 2 節）。
class_name PlayerRepository
extends RefCounted


## login の結果で、保持しているプレイヤーと所持データを置き換える（差分ではなく全量）。
func replace(_state: PlayerState) -> void:
	push_error("未実装: PlayerRepository.replace")


## 今保持している状態。ログイン前・破棄後は空の PlayerState（null にしない）。
func current() -> PlayerState:
	push_error("未実装: PlayerRepository.current")
	return null


## 保持を空にする（セッション破棄のとき）。
func clear() -> void:
	push_error("未実装: PlayerRepository.clear")
