## 規約本文（HTML）の取得の契約（architecture.md 7 節）。
##
## 目的: 取得の UseCase が通信の実装を知らず、テストでは偽物に差し替えられるようにする。
## 実装: contexts/agreement/data/repositories/agreement_document_http_repository.gd。
## 失敗は例外にせず、結果の error（AppError）で返す。
class_name AgreementDocumentRepository
extends RefCounted


## 規約の URL（sys_agreement.url。絶対 URL か "/" 始まりの相対パス）から HTML を取得する。
func fetch_document(_url: String) -> FetchAgreementDocumentResult:
	push_error("未実装: AgreementDocumentRepository.fetch_document")
	return null
