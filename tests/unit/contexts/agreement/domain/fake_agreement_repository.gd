## 規約の UseCase のテスト用の偽 AgreementRepository。
## consent_results / pending_results を先頭から消費し、呼ばれた記録（calls・keys）を残す。
class_name FakeAgreementRepository
extends AgreementRepository

var pending_results: Array[PendingAgreementsResult] = []
var consent_results: Array[Result] = []
## 呼ばれた順序（"pending" / "consent:<id>"）
var calls: Array[String] = []
## consent に渡された冪等キー
var keys: Array[String] = []


func fetch_pending() -> PendingAgreementsResult:
	calls.append("pending")
	if pending_results.is_empty():
		return PendingAgreementsResult.new([], AppError.new(AppError.Kind.SERVER_ERROR, "想定外"))
	return pending_results.pop_front()


func consent(sys_agreement_id: int, idempotency_key: String) -> Result:
	calls.append("consent:%d" % sys_agreement_id)
	keys.append(idempotency_key)
	if consent_results.is_empty():
		return Result.failure(AppError.new(AppError.Kind.SERVER_ERROR, "想定外"))
	return consent_results.pop_front()


## 業務エラーの失敗。
static func business(code: int) -> Result:
	var error := AppError.new(AppError.Kind.BUSINESS)
	error.error_code = code
	return Result.failure(error)


## 規約 ids を持つ成功の取得結果。
static func pending_ok(ids: Array[int] = []) -> PendingAgreementsResult:
	var agreements: Array[PendingAgreement] = []
	for id in ids:
		agreements.append(PendingAgreement.new(id, "1.0", "規約%d" % id))
	return PendingAgreementsResult.new(agreements)


## 失敗の取得結果。
static func pending_failure(kind: AppError.Kind) -> PendingAgreementsResult:
	return PendingAgreementsResult.new([], AppError.new(kind))
