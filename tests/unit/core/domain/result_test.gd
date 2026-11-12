## Result の単体テスト。成功・失敗の基底が、ok と error を正しく持つことを確かめる。
extends GdUnitTestSuite


## 前提: なし。操作: Result.success()。期待: ok が true で error は null。
## UseCase が成功を返したとき、呼び出し側が error を見ずに済むことを守る。
func test_success_has_no_error() -> void:
	var result := Result.success()
	assert_bool(result.ok).is_true()
	assert_object(result.error).is_null()


## 前提: AppError(NETWORK)。操作: Result.failure(error)。期待: ok が false で error が同じ物。
## 失敗の理由が失われず、kind で分岐できることを守る。
func test_failure_carries_error() -> void:
	var error := AppError.new(AppError.Kind.NETWORK, "x")
	var result := Result.failure(error)
	assert_bool(result.ok).is_false()
	assert_object(result.error).is_same(error)
	assert_int(result.error.kind).is_equal(AppError.Kind.NETWORK)
