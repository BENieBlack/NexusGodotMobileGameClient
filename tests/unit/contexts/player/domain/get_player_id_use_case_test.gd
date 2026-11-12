## GetPlayerIdUseCase の単体テスト: login で取り込んだ my_id を返し、未ログインなら空文字を返す。
extends GdUnitTestSuite


## 前提: 状態が空 → login 反映後 → セッション破棄後。期待: 空文字 → my_id → 空文字
## （破棄後に前のプレイヤーの ID を見せない）。
func test_returns_my_id_and_empty_when_cleared() -> void:
	var repository := LocalPlayerRepository.new()
	var use_case := GetPlayerIdUseCase.new(repository)
	assert_str(use_case.handle()).is_empty()
	ApplyLoginDataUseCase.new(repository).handle({"my_id": "abc"}, {})
	assert_str(use_case.handle()).is_equal("abc")
	repository.clear()
	assert_str(use_case.handle()).is_empty()
