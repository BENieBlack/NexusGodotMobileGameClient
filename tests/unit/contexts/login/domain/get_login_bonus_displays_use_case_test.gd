## GetLoginBonusDisplaysUseCase の単体テスト（free-diamond-item client_design.md 3-3）。
extends GdUnitTestSuite


## 偽の MstItemRepository。names の ID だけ名前つきで返し、無ければ null。引いた ID を記録する。
class FakeItems:
	extends MstItemRepository
	var names: Dictionary = {}
	var asked: Array[String] = []

	func get_by_id(id: String) -> MstItem:
		asked.append(id)
		if not names.has(id):
			return null
		var item := MstItem.new()
		item.id = id
		item.name = str(names[id])
		return item


var _repository: LocalLoginBonusRepository
var _items: FakeItems


func before_test() -> void:
	_repository = LocalLoginBonusRepository.new()
	_items = FakeItems.new()


func _use_case(items: MstItemRepository) -> GetLoginBonusDisplaysUseCase:
	return GetLoginBonusDisplaysUseCase.new(GetLoginBonusesUseCase.new(_repository), items)


## 前提: item と unit の 2 件。期待: item だけ名前を引き、unit は引かない（item_name は空）。
func test_only_item_type_is_looked_up() -> void:
	_items.names = {"free_diamond": "無償ダイヤ"}
	var bonuses: Array[LoginBonus] = [
		LoginBonus.new("u1", "item", "free_diamond", 100),
		LoginBonus.new("u2", "unit", "7", 1),
	]
	_repository.replace(bonuses)
	var displays := _use_case(_items).handle()
	assert_int(displays.size()).is_equal(2)
	assert_str(displays[0].item_name).is_equal("無償ダイヤ")
	assert_str(displays[1].item_name).is_empty()
	assert_array(_items.asked).contains_exactly(["free_diamond"])


## 前提: 名前が引けない（null）・name が空。期待: item_name は空で落ちない。
func test_missing_or_empty_name_is_empty() -> void:
	_items.names = {"a": ""}
	var bonuses: Array[LoginBonus] = [
		LoginBonus.new("u1", "item", "a", 1),
		LoginBonus.new("u2", "item", "b", 1),
	]
	_repository.replace(bonuses)
	var displays := _use_case(_items).handle()
	assert_str(displays[0].item_name).is_empty()
	assert_str(displays[1].item_name).is_empty()


## 前提: Repository が null（配線の取りこぼし）。期待: 落ちずに item_name 空。
func test_null_repository_does_not_crash() -> void:
	var bonuses: Array[LoginBonus] = [LoginBonus.new("u1", "item", "a", 1)]
	_repository.replace(bonuses)
	var displays := _use_case(null).handle()
	assert_str(displays[0].item_name).is_empty()
	assert_int(displays[0].bonus.amount).is_equal(1)


## 前提: 受取が空。期待: 空の一覧。
func test_empty_bonuses() -> void:
	assert_array(_use_case(_items).handle()).is_empty()
