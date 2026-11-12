## 未同意の規約の取得結果。成功なら agreements を持つ（無ければ空。空は「見せる規約が無い」で失敗ではない）。
## AgreementRepository.fetch_pending() と FetchPendingAgreementsUseCase が共通で返す。
## 失敗（通信・業務エラーなど）は握りつぶさず error で返し、呼び出し元が再試行できるようにする。
class_name PendingAgreementsResult
extends Result

var agreements: Array[SysAgreement] = []


func _init(p_agreements: Array[SysAgreement] = [], p_error: AppError = null) -> void:
	super(p_error == null, p_error)
	agreements = p_agreements
