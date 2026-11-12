## GetLoginBonusesUseCase の単体テスト: login の Repository が持つ受取の一覧をそのまま返す。
extends GdUnitTestSuite


## 前提: 空 → 1 件を保持。期待: 空 → 1 件（ログインボーナス画面が通信せずに表示できる）。
func test_returns_held_bonuses() -> void:
	var repository := LocalLoginBonusRepository.new()
	var use_case := GetLoginBonusesUseCase.new(repository)
	assert_array(use_case.handle()).is_empty()
	var bonuses: Array[LoginBonus] = [LoginBonus.new("u", "gold", "gold", 100)]
	repository.replace(bonuses)
	assert_int(use_case.handle().size()).is_equal(1)
