## GetAccessTokenUseCase の単体テスト: 保存中のアクセストークンをそのまま返す（無ければ空文字）。
extends GdUnitTestSuite


## 前提: トークンが無い / 保存済み。操作: handle。期待: 空文字 / 保存した値。
func test_returns_saved_access_token_or_empty() -> void:
	var tokens := FakeApiClient.FakeAuth.new()
	var use_case := GetAccessTokenUseCase.new(tokens)
	assert_str(use_case.handle()).is_empty()
	tokens.save_tokens("a1", "r1")
	assert_str(use_case.handle()).is_equal("a1")
