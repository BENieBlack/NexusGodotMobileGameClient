## AgreementDocumentHttpRepository の単体テスト。URL の解決と、偽の通信での取得・失敗の分類を確かめる。
extends GdUnitTestSuite

const ORIGIN := "http://localhost:8090"

var _client: FakeApiClient
var _repository: AgreementDocumentHttpRepository


func before_test() -> void:
	_client = auto_free(FakeApiClient.new())
	_repository = AgreementDocumentHttpRepository.new(_client)


## 期待: 絶対 URL はそのまま、"/" 始まりは origin に付ける（末尾の / は重ねない）。
func test_resolve_url_absolute_and_relative() -> void:
	var resolve := AgreementDocumentHttpRepository.resolve_url
	assert_str(resolve.call("https://example.com/t.html", ORIGIN)).is_equal(
		"https://example.com/t.html"
	)
	assert_str(resolve.call("http://example.com/t.html", ORIGIN)).is_equal(
		"http://example.com/t.html"
	)
	assert_str(resolve.call("/legal/a.html", ORIGIN)).is_equal(ORIGIN + "/legal/a.html")
	assert_str(resolve.call("/legal/a.html", ORIGIN + "/")).is_equal(ORIGIN + "/legal/a.html")


## 期待: 空・相対（/ なし）・プロトコル相対（//）・http 以外のスキームは不正（空文字）。
func test_resolve_url_invalid() -> void:
	var resolve := AgreementDocumentHttpRepository.resolve_url
	for bad in [
		"", "  ", "terms/a.html", "//evil.example/a.html", "javascript:alert(1)", "ftp://x/y"
	]:
		assert_str(resolve.call(bad, ORIGIN)).is_equal("")


## 期待: 成功は本文を UTF-8 の文字列にして返す。認証ヘッダーは付かない。
func test_fetch_success_decodes_utf8() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, "<p>利用規約</p>")
	var result := await _repository.fetch_document("/legal/a.html")

	assert_bool(result.ok).is_true()
	assert_str(result.html).is_equal("<p>利用規約</p>")
	assert_int(_client.calls.size()).is_equal(1)
	assert_str(_client.calls[0]["method"]).is_equal("GET")
	assert_str(_client.calls[0]["url"]).ends_with("/legal/a.html")
	assert_str(FakeApiClient.header_value(_client.calls[0]["headers"], "Authorization")).is_equal(
		""
	)


## 期待: 不正な URL は通信せず LOCAL の失敗。
func test_fetch_invalid_url_fails_without_request() -> void:
	var result := await _repository.fetch_document("not-a-url")

	assert_bool(result.ok).is_false()
	assert_int(result.error.kind).is_equal(AppError.Kind.LOCAL)
	assert_int(_client.calls.size()).is_equal(0)


## 期待: 通信失敗・タイムアウトは NETWORK。HTTP 200 以外は SERVER_ERROR。本文が空（空白のみ）は PARSE。
func test_fetch_failures_are_classified() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.network_error()
	var network := await _repository.fetch_document("/legal/a.html")
	assert_int(network.error.kind).is_equal(AppError.Kind.NETWORK)

	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(404, "not found")
	var missing := await _repository.fetch_document("/legal/a.html")
	assert_int(missing.error.kind).is_equal(AppError.Kind.SERVER_ERROR)

	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, " \n ")
	var empty := await _repository.fetch_document("/legal/a.html")
	assert_int(empty.error.kind).is_equal(AppError.Kind.PARSE)
