## ログインボーナス画面の表示用の値を作る UseCase（client_design.md 3-3）。
##
## 目的: 直近の login の受取（GetLoginBonusesUseCase）に、type が item の行の名前（mst_item の l10n）を
##       添えて返す。presenter が Repository を直接触らないための窓口。
## 流れ:
##   1. 受取の一覧を取る
##   2. 行ごとに、type が item のときだけ MstItemRepository から名前を引く（unit などは引かない）
##   3. 名前が引けない（行なし・name が空・Repository が null）は item_name を空にする。例外にしない
## 行数は数件なのでキャッシュは持たない。言語は Repository が持つ（この UseCase は知らない）。
class_name GetLoginBonusDisplaysUseCase
extends RefCounted

var _get_login_bonuses: GetLoginBonusesUseCase
var _mst_item_repository: MstItemRepository


func _init(
	get_login_bonuses: GetLoginBonusesUseCase, mst_item_repository: MstItemRepository
) -> void:
	_get_login_bonuses = get_login_bonuses
	_mst_item_repository = mst_item_repository


## 表示用の値の一覧を返す（受取と同じ順）。
func handle() -> Array[LoginBonusDisplay]:
	var displays: Array[LoginBonusDisplay] = []
	for bonus in _get_login_bonuses.handle():
		displays.append(LoginBonusDisplay.new(bonus, _lookup_item_name(bonus)))
	return displays


## type が item の行だけ名前を引く。引けなければ空文字。
func _lookup_item_name(bonus: LoginBonus) -> String:
	if bonus.type != LoginBonus.TYPE_ITEM or _mst_item_repository == null:
		return ""
	var item := _mst_item_repository.get_by_id(bonus.id)
	if item == null:
		return ""
	return item.name
