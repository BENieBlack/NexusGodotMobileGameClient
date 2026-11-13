## FetchAgreementDocumentUseCase の結果。成功なら規約本文の HTML（UTF-8 の文字列）を持つ。
##
## 項目:
##   ok / error   Result と同じ。失敗は AppError（通信断・HTTP 200 以外・本文が空・URL 不正）
##   html         成功のときの本文。失敗のときは空
## AgreementDocumentRepository も同じ型を返す（変換だけのために型を増やさない。軽量化の指針）。
class_name FetchAgreementDocumentResult
extends Result

var html: String = ""


func _init(p_html: String = "", p_error: AppError = null) -> void:
	super(p_error == null, p_error)
	html = p_html
