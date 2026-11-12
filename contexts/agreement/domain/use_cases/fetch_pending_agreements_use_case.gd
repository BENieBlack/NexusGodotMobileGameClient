## 未同意の規約を取得する UseCase（GET /agreement/pending。client_design.md 3-1）。
##
## 目的: 規約画面の読み込み時に呼ぶ。結果が空（agreements が空）なら、画面を見せずにログインボーナスへ進む。
## 失敗の扱い: 握りつぶさず、失敗の結果（AppError）をそのまま返す。呼び出し元（規約画面）が
##   エラー文と「再試行」を出し、取得から再試行できるようにする（取得失敗でも規約を飛ばさない。1-1）。
## GET なので冪等キーは付けない。
class_name FetchPendingAgreementsUseCase
extends RefCounted

var _agreement_repository: AgreementRepository


func _init(agreement_repository: AgreementRepository) -> void:
	_agreement_repository = agreement_repository


func handle() -> PendingAgreementsResult:
	return await _agreement_repository.fetch_pending()
