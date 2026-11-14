## プレイヤーレベルマスター（mst_player_level）を読む契約。contexts から読み取り専用で使う（architecture.md 2-1）。
## 実装: master_data/data/repositories/local_mst_player_level_repository.gd（SQLite）。
class_name MstPlayerLevelRepository
extends RefCounted


## level の行を返す。行が無い・テーブルが無い・DB が開けないときは null（例外にしない）。
func get_by_level(_level: int) -> MstPlayerLevel:
	push_error("未実装: MstPlayerLevelRepository.get_by_level")
	return null
