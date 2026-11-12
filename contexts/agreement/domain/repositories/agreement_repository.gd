## 規約 API（未同意の取得・同意）の契約（architecture.md 7 節）。
##
## 目的: 規約の UseCase が通信の実装を知らずに、テストでは偽物に差し替えられるようにする。
## 実装: contexts/agreement/data/repositories/agreement_api_repository.gd。
## 失敗は例外にせず、結果の error（AppError）で返す。
class_name AgreementRepository
extends RefCounted


## GET /agreement/pending。未同意の規約の一覧。
func fetch_pending() -> PendingAgreementsResult:
	push_error("未実装: AgreementRepository.fetch_pending")
	return null


## POST /agreement/consent。規約 1 件に同意する。idempotency_key は冪等キー（必ず付ける）。
## 業務エラー（24001 / 24002 など）は失敗（BUSINESS）として返す。扱いは UseCase が決める。
func consent(_sys_agreement_id: int, _idempotency_key: String) -> Result:
	push_error("未実装: AgreementRepository.consent")
	return null
