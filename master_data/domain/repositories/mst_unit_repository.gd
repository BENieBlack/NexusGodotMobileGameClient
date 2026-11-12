## ユニットマスター（mst_unit）を読む契約。contexts から読み取り専用で使う（architecture.md 2-1）。
## 実装: master_data/data/repositories/local_mst_unit_repository.gd（SQLite）。
class_name MstUnitRepository
extends RefCounted


## 全件を返す（並びは実装が決める）。DB が開けていなければ空配列。
func get_all() -> Array[MstUnit]:
	push_error("未実装: MstUnitRepository.get_all")
	return []


## id で 1 件返す。無ければ null。
func get_by_id(_id: String) -> MstUnit:
	push_error("未実装: MstUnitRepository.get_by_id")
	return null
