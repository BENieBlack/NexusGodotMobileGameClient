## 規約本文（HTML）を取得する UseCase。規約の閲覧画面が開いたとき・再試行のときに呼ぶ。
##
## 失敗の扱い: 握りつぶさず、失敗の結果（AppError）をそのまま返す。閲覧画面がエラー文・「再試行」・
##   「ブラウザで開く」を出す。GET なので冪等キーは付けない。
class_name FetchAgreementDocumentUseCase
extends RefCounted

var _document_repository: AgreementDocumentRepository


func _init(document_repository: AgreementDocumentRepository) -> void:
	_document_repository = document_repository


func handle(url: String) -> FetchAgreementDocumentResult:
	return await _document_repository.fetch_document(url)
