## CheckMasterDataUseCase.handle() の結果（client_design.md 5 節）。
##
## status:
##   UP_TO_DATE  更新不要
##   UPDATED     差分を取得して DB を切り替えた
##   IN_PROGRESS 別の同期が実行中のため何もしなかった（更新済みの意味ではない。呼び出し側は結果を
##               待たずに続けてよい。実行中の同期は、終了後に 1 回だけ再実行される）
##   FAILED      更新できなかった。端末は同梱（または前回取得済み）の DB のまま。呼び出し元（タイトル）は
##               止めずに続行し、通知する。ok = false で、error に理由（AppError）が入る
## message: 人が読む補足（ログ・通知用）。
class_name CheckMasterDataResult
extends Result

enum Status { UP_TO_DATE, UPDATED, FAILED, IN_PROGRESS }

var status: Status = Status.UP_TO_DATE
var message: String = ""


func _init(
	p_status: Status = Status.UP_TO_DATE, p_message: String = "", p_error: AppError = null
) -> void:
	super(p_status != Status.FAILED, p_error)
	status = p_status
	message = p_message
