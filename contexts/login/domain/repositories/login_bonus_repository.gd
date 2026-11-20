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


## 保持を空にする（セッション破棄のとき。受取結果と段の進捗の両方）。
func clear() -> void:
	push_error("未実装: LoginBonusRepository.clear")


## 通常・VIP の段の進捗で置き換える（login 応答・list 応答・再受け取りの応答のあと。全量）。
func replace_calendars(_calendars: LoginBonusCalendars) -> void:
	push_error("未実装: LoginBonusRepository.replace_calendars")


## 保持している段の進捗。ログイン前・破棄後・旧サーバー（新キー無し）は、両方 null の束（null にしない）。
func calendars() -> LoginBonusCalendars:
	push_error("未実装: LoginBonusRepository.calendars")
	return LoginBonusCalendars.new()
