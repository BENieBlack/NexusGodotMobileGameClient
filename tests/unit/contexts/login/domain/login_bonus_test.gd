## LoginBonus.is_free_diamond() の単体テスト（free-diamond-item client_design.md 3-2）。
extends GdUnitTestSuite


## 前提: type が item・id が free_diamond。期待: 真。
func test_item_free_diamond_is_true() -> void:
	assert_bool(LoginBonus.new("u", "item", "free_diamond", 1).is_free_diamond()).is_true()


## 前提: type は item だが id が違う。期待: 偽（id だけでなく type も見る）。
func test_other_item_is_false() -> void:
	assert_bool(LoginBonus.new("u", "item", "stamina_50", 1).is_free_diamond()).is_false()


## 前提: id は free_diamond だが type が違う（旧 diamond など）。期待: 偽。
func test_other_type_is_false() -> void:
	assert_bool(LoginBonus.new("u", "diamond", "free_diamond", 1).is_free_diamond()).is_false()
