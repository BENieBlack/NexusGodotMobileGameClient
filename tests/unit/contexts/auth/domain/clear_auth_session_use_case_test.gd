## ClearAuthSessionUseCase の単体テスト。
extends GdUnitTestSuite


## 前提: トークンを保存済み。操作: handle。期待: アクセス・リフレッシュの両方が空になる。
func test_clears_both_tokens() -> void:
	var tokens := FakeApiClient.FakeAuth.new("a", "r")
	var result := ClearAuthSessionUseCase.new(tokens).handle()
	assert_bool(result.ok).is_true()
	assert_str(tokens.access).is_empty()
	assert_str(tokens.refresh).is_empty()
