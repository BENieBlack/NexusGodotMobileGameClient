## IdempotencyKey の単体テスト（client_design.md 3-4 の再利用規則）。
extends GdUnitTestSuite


## 前提: なし。操作: generate を 2 回。
## 期待: UUID v4 の形式（8-4-4-4-12、版 4、variant 8/9/a/b）で、2 回の値が違う。
## 形式を守るのはサーバーが検証しないため自由だが、衝突しないこと（乱数が効いていること）を守る。
func test_generate_returns_unique_uuid_v4() -> void:
	var regex := RegEx.create_from_string(
		"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
	)
	var first := IdempotencyKey.generate()
	var second := IdempotencyKey.generate()
	assert_object(regex.search(first)).is_not_null()
	assert_object(regex.search(second)).is_not_null()
	assert_str(first).is_not_equal(second)


## 前提: 直前の失敗の種別。操作: can_reuse。
## 期待: 通信断・409・503（メンテ・基盤不達）・500 などは再利用、業務エラー（299）だけ作り直し。
## 業務エラーは結果が保存され、同じキーで送ると同じエラーが返り続けるため（3-4 の表）。
func test_can_reuse_follows_the_design_table() -> void:
	for kind: AppError.Kind in [
		AppError.Kind.NETWORK,
		AppError.Kind.CONFLICT,
		AppError.Kind.SERVER_BUSY,
		AppError.Kind.MAINTENANCE,
		AppError.Kind.SERVER_ERROR,
		AppError.Kind.SESSION_EXPIRED,
	]:
		assert_bool(IdempotencyKey.can_reuse(kind)).is_true()
	assert_bool(IdempotencyKey.can_reuse(AppError.Kind.BUSINESS)).is_false()
