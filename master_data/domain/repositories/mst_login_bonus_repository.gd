## 通常のログインボーナスのマスター（mst_login_bonus と mst_login_bonus_content）を読む契約。
## contexts から読み取り専用で使う（architecture.md 2-1）。
## 実装: master_data/data/repositories/local_mst_login_bonus_repository.gd（SQLite）。
class_name MstLoginBonusRepository
extends RefCounted


## id の本体と報酬行を引き、結果の種別（見つかった／行が無い／読めない）つきで返す。例外にしない。
func find_by_id(_id: String) -> MstLoginBonusLookup:
	push_error("未実装: MstLoginBonusRepository.find_by_id")
	return MstLoginBonusLookup.new()


## 見つかったときだけ本体を返す。行が無い・テーブルが無い・DB が開けないときは null（例外にしない）。
func get_by_id(id: String) -> MstLoginBonus:
	return find_by_id(id).bonus
