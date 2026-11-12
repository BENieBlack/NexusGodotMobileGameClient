## 規約 1 件に同意する UseCase（POST /agreement/consent。client_design.md 3-1・3-4）。
##
## 目的: 規約画面の「すべての規約に同意して続ける」で、規約ごとに 1 件ずつ直列に呼ぶ。
## 流れ（handle）:
##   1. 冪等キーを決める（規約ごとに呼び出し元が持つ。空なら作る）。X-Unique-Request-Identifier に必ず付ける（D6）
##   2. 送信する。成功ならそのまま成功
##   3. 業務エラーのうち次の 2 つだけ、画面に出さずに処理する
##      - 24002（同意済み）: 目的は達成済みなので成功扱い（二重送信・別端末での同意など）
##      - 24001（規約が存在しない・公開前・必須でなくなった）: 一覧が古い。未同意の一覧を取り直して
##        refetched = true と agreements で返す。取り直しに失敗したら、その失敗を返す（再試行できる）
##   4. それ以外の失敗はそのまま返す
## 冪等キーの扱いは LoginUseCase と同じ（失敗後の再送は IdempotencyKey.can_reuse で決める。成功したら捨てる）。
class_name ConsentAgreementUseCase
extends RefCounted

## 同意済み（AGREEMENT_ALREADY_CONSENTED）。成功扱いにする
const ERROR_ALREADY_CONSENTED := 24002
## 規約が存在しない・公開前・必須でない（AGREEMENT_NOT_FOUND）。一覧を取り直す
const ERROR_NOT_FOUND := 24001

var _agreement_repository: AgreementRepository


func _init(agreement_repository: AgreementRepository) -> void:
	_agreement_repository = agreement_repository


func handle(sys_agreement_id: int, idempotency_key: String = "") -> ConsentAgreementResult:
	# --- 1. 冪等キー ---
	var key := idempotency_key if idempotency_key != "" else IdempotencyKey.generate()

	# --- 2. 送信 ---
	var result := await _agreement_repository.consent(sys_agreement_id, key)
	if result.ok:
		return ConsentAgreementResult.new()

	# --- 3. 24002 は成功、24001 は取り直し ---
	if result.error.kind == AppError.Kind.BUSINESS:
		if result.error.error_code == ERROR_ALREADY_CONSENTED:
			return ConsentAgreementResult.new()
		if result.error.error_code == ERROR_NOT_FOUND:
			var pending := await _agreement_repository.fetch_pending()
			if not pending.ok:
				return ConsentAgreementResult.new(pending.error)
			return ConsentAgreementResult.new(null, true, pending.agreements)

	# --- 4. その他の失敗 ---
	return ConsentAgreementResult.new(result.error)
