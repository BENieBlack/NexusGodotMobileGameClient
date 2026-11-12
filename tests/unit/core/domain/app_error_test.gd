## AppError の単体テスト。既定値が「情報なし」を表すことを確かめる。
extends GdUnitTestSuite


## 前提: kind と message だけで作る。操作: 付帯情報を読む。
## 期待: error_code は -1（無し）、retry_after は 0、maintenance は空。
## 表示側が「コードがあるか」を -1 で判定するため、既定値がずれると文言が壊れる。
func test_defaults_mean_no_extra_info() -> void:
	var error := AppError.new(AppError.Kind.BUSINESS, "m")
	assert_int(error.kind).is_equal(AppError.Kind.BUSINESS)
	assert_str(error.message).is_equal("m")
	assert_int(error.error_code).is_equal(-1)
	assert_int(error.retry_after).is_equal(0)
	assert_dict(error.maintenance).is_empty()
