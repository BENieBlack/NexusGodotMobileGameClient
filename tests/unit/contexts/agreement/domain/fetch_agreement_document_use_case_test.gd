## FetchAgreementDocumentUseCase の単体テスト（偽の Repository。通信しない）。
extends GdUnitTestSuite


## 期待: 成功は HTML をそのまま返し、Repository へ URL を渡す。
func test_success_returns_html() -> void:
	var repository := FakeAgreementDocumentRepository.new()
	repository.results = [FakeAgreementDocumentRepository.ok("<p>x</p>")]
	var result := await FetchAgreementDocumentUseCase.new(repository).handle("/legal/a.html")

	assert_bool(result.ok).is_true()
	assert_str(result.html).is_equal("<p>x</p>")
	assert_array(repository.urls).contains_exactly(["/legal/a.html"])


## 期待: 失敗は握りつぶさず、AppError の種別をそのまま返す。
func test_failure_is_passed_through() -> void:
	var repository := FakeAgreementDocumentRepository.new()
	repository.results = [FakeAgreementDocumentRepository.failure(AppError.Kind.NETWORK)]
	var result := await FetchAgreementDocumentUseCase.new(repository).handle("/legal/a.html")

	assert_bool(result.ok).is_false()
	assert_int(result.error.kind).is_equal(AppError.Kind.NETWORK)
	assert_str(result.html).is_equal("")
