## アイテムマスター（mst_item）を読む契約。contexts から読み取り専用で使う（architecture.md 2-1）。
## 実装: master_data/data/repositories/local_mst_item_repository.gd（SQLite）。
## 言語は引数にしない。Repository が構築時に持つ（API の Accept-Language と同じ値。client_design.md 5-2）。
class_name MstItemRepository
extends RefCounted


## id の行を返す。mst_item に行が無い・テーブルが無い・DB が開けないときは null（例外にしない）。
## mst_item の行だけ有って l10n の行（指定言語）が無いときは、name が空の MstItem を返す。
func get_by_id(_id: String) -> MstItem:
	push_error("未実装: MstItemRepository.get_by_id")
	return null
