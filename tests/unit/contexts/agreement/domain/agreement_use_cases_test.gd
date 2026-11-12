## 規約の UseCase（未同意の取得・同意）の単体テスト（client_design.md 3-1・3-4）。
extends GdUnitTestSuite

var _repository: FakeAgreementRepository


func before_test() -> void:
	_repository = FakeAgreementRepository.new()


## 前提: 未同意が 1 件。操作: FetchPendingAgreementsUseCase.handle。期待: その一覧が返る。
func test_fetch_returns_agreements() -> void:
	_repository.pending_results = [FakeAgreementRepository.pending_ok([1])]
	var result := await FetchPendingAgreementsUseCase.new(_repository).handle()
	assert_bool(result.ok).is_true()
	assert_int(result.agreements.size()).is_equal(1)


## 前提: 取得が通信失敗。期待: 握りつぶさず失敗で返す（画面が再試行を出せる。規約を飛ばさない）。
func test_fetch_failure_is_returned() -> void:
	_repository.pending_results = [FakeAgreementRepository.pending_failure(AppError.Kind.NETWORK)]
	var result := await FetchPendingAgreementsUseCase.new(_repository).handle()
	assert_bool(result.ok).is_false()
	assert_int(result.error.kind).is_equal(AppError.Kind.NETWORK)


## 前提: consent が成功。操作: handle(5, "k")。期待: 成功、取り直しなし、渡した冪等キーで送る。
func test_consent_success_uses_given_key() -> void:
	_repository.consent_results = [Result.success()]
	var result := await ConsentAgreementUseCase.new(_repository).handle(5, "k")
	assert_bool(result.ok).is_true()
	assert_bool(result.refetched).is_false()
	assert_array(_repository.keys).contains_exactly(["k"])
	assert_array(_repository.calls).contains_exactly(["consent:5"])


## 前提: consent が 24002（同意済み）。期待: 成功扱い（目的は達成済み。取り直しもしない）。
func test_consent_24002_is_success() -> void:
	_repository.consent_results = [FakeAgreementRepository.business(24002)]
	var result := await ConsentAgreementUseCase.new(_repository).handle(5, "k")
	assert_bool(result.ok).is_true()
	assert_bool(result.refetched).is_false()
	assert_array(_repository.calls).contains_exactly(["consent:5"])


## 前提: consent が 24001（規約が存在しない）で、取り直した一覧は 1 件。
## 期待: refetched = true で新しい一覧を返す（呼び出し元が一覧を差し替えて続ける）。
func test_consent_24001_refetches_pending() -> void:
	_repository.consent_results = [FakeAgreementRepository.business(24001)]
	_repository.pending_results = [FakeAgreementRepository.pending_ok([7])]
	var result := await ConsentAgreementUseCase.new(_repository).handle(5, "k")
	assert_bool(result.ok).is_true()
	assert_bool(result.refetched).is_true()
	assert_int(result.agreements[0].sys_agreement_id).is_equal(7)
	assert_array(_repository.calls).contains_exactly(["consent:5", "pending"])


## 前提: consent が 24001、取り直しも通信失敗。期待: その失敗を返す（握りつぶさず、再試行できる）。
func test_consent_24001_refetch_failure_is_returned() -> void:
	_repository.consent_results = [FakeAgreementRepository.business(24001)]
	_repository.pending_results = [FakeAgreementRepository.pending_failure(AppError.Kind.NETWORK)]
	var result := await ConsentAgreementUseCase.new(_repository).handle(5, "k")
	assert_bool(result.ok).is_false()
	assert_int(result.error.kind).is_equal(AppError.Kind.NETWORK)
	assert_bool(result.refetched).is_false()


## 前提: consent が 409 / 他の業務エラー。期待: そのまま失敗で返す（取り直さない）。
func test_consent_other_failures_are_returned() -> void:
	var conflict := Result.failure(AppError.new(AppError.Kind.CONFLICT))
	_repository.consent_results = [conflict, FakeAgreementRepository.business(99999)]
	var use_case := ConsentAgreementUseCase.new(_repository)
	assert_int((await use_case.handle(5, "k")).error.kind).is_equal(AppError.Kind.CONFLICT)
	assert_int((await use_case.handle(5, "k")).error.error_code).is_equal(99999)
	assert_array(_repository.calls).contains_exactly(["consent:5", "consent:5"])


## 前提: キーを渡さない。期待: キー無しで送らず、UUID を作って付ける（D6）。
func test_consent_generates_key_when_empty() -> void:
	_repository.consent_results = [Result.success()]
	await ConsentAgreementUseCase.new(_repository).handle(5)
	assert_str(_repository.keys[0]).has_length(36)


## 前提: 実 API 経由（成功応答の本文が `[]`）で ConsentAgreementUseCase を動かす。
## 期待: 成功（refetched なし）。同意の成功が失敗扱いにならない経路全体を守る。
func test_consent_success_with_empty_array_body_through_api_repository() -> void:
	var client: FakeApiClient = auto_free(FakeApiClient.new())
	client.configure(FakeApiClient.FakeAuth.new("tok", "ref"), null)
	client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, "[]")
	var use_case := ConsentAgreementUseCase.new(AgreementApiRepository.new(client))
	var result := await use_case.handle(5, "k")
	assert_bool(result.ok).is_true()
	assert_bool(result.refetched).is_false()
