## ConsentAgreementUseCase の結果。成功か失敗かに加え、「未同意の一覧を取り直したか」を持つ。
##
## 項目:
##   ok / error        Result と同じ。24002（同意済み）は成功扱い。24001 は取り直しに成功したら成功
##   refetched         24001（規約が存在しない・公開前など）で、未同意の一覧を取り直したとき true
##   agreements        refetched が true のときの、取り直した未同意の一覧（呼び出し元は一覧を差し替えて続ける）
class_name ConsentAgreementResult
extends Result

var refetched: bool = false
var agreements: Array[PendingAgreement] = []


func _init(
	p_error: AppError = null, p_refetched: bool = false, p_agreements: Array[PendingAgreement] = []
) -> void:
	super(p_error == null, p_error)
	refetched = p_refetched
	agreements = p_agreements
