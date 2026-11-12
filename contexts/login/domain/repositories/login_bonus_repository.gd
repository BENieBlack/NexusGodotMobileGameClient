## ログインボーナスの保持先の契約（architecture.md 7 節）。
##
## 目的: LoginUseCase が保持の実装を知らずに、テストでは偽物に差し替えられるようにする。
## 実装: contexts/login/data/repositories/local_login_bonus_repository.gd（メモリのみ）。
class_name LoginBonusRepository
extends RefCounted


## 今回の login の受取結果で置き換える（全量。付与が無い日は空の配列）。
func replace(_bonuses: Array[LoginBonus]) -> void:
	push_error("未実装: LoginBonusRepository.replace")


## 保持している受取結果。ログイン前・破棄後は空。
func list() -> Array[LoginBonus]:
	push_error("未実装: LoginBonusRepository.list")
	return []


## 保持を空にする（セッション破棄のとき）。
func clear() -> void:
	push_error("未実装: LoginBonusRepository.clear")
