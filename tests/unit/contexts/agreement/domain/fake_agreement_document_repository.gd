## 規約本文の取得のテスト用の偽 AgreementDocumentRepository。
## results を先頭から消費し、渡された URL を urls に残す。wait_frames > 0 なら、その分だけ待ってから返す
## （取得の保留中に起きることを再現するため）。
class_name FakeAgreementDocumentRepository
extends AgreementDocumentRepository

var results: Array[FetchAgreementDocumentResult] = []
var urls: Array[String] = []
var wait_frames: int = 0


func fetch_document(url: String) -> FetchAgreementDocumentResult:
	urls.append(url)
	for i in range(wait_frames):
		await Engine.get_main_loop().process_frame
	if results.is_empty():
		return FetchAgreementDocumentResult.new("", AppError.new(AppError.Kind.SERVER_ERROR))
	return results.pop_front()


static func ok(html: String) -> FetchAgreementDocumentResult:
	return FetchAgreementDocumentResult.new(html)


static func failure(kind: AppError.Kind) -> FetchAgreementDocumentResult:
	return FetchAgreementDocumentResult.new("", AppError.new(kind))
