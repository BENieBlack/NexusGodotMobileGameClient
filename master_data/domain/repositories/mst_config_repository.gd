## 設定マスター（mst_config）を読む契約。contexts から読み取り専用で使う（architecture.md 2-1）。
## 実装: master_data/data/repositories/local_mst_config_repository.gd（SQLite）。
class_name MstConfigRepository
extends RefCounted


## id の行を返す。行が無い・テーブルが無い・DB が開けないときは null（例外にしない）。
func get_by_id(_id: String) -> MstConfig:
	push_error("未実装: MstConfigRepository.get_by_id")
	return null
