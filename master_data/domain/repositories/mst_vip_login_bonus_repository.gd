## VIP ログインボーナスのマスター（mst_vip_login_bonus と mst_vip_login_bonus_content）を読む契約。
## 実装: master_data/data/repositories/local_mst_vip_login_bonus_repository.gd（SQLite）。
class_name MstVipLoginBonusRepository
extends RefCounted


## id の本体と報酬行を引き、結果の種別（見つかった／行が無い／読めない）つきで返す。例外にしない。
func find_by_id(_id: String) -> MstVipLoginBonusLookup:
	push_error("未実装: MstVipLoginBonusRepository.find_by_id")
	return MstVipLoginBonusLookup.new()


## 見つかったときだけ本体を返す。引けないときは null。
func get_by_id(id: String) -> MstVipLoginBonus:
	return find_by_id(id).bonus
