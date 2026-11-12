## AuthenticateUseCase の単体テスト（client_design.md 3-3）: sign_in / sign_up の振り分け。
##
## 偽の AuthRepository と偽のトークン供給（FakeApiClient.FakeAuth）で、最初に呼ぶ API、
## 10002 / 10004 の切り替え（1 回だけ）、打ち切り、トークンの保存を確かめる。
extends GdUnitTestSuite

var _repository: FakeAuthRepository
var _tokens: FakeApiClient.FakeAuth
var _use_case: AuthenticateUseCase


func before_test() -> void:
	_repository = FakeAuthRepository.new()
	_tokens = FakeApiClient.FakeAuth.new()
	_use_case = AuthenticateUseCase.new(_repository, _tokens)


## 前提: 保存トークンが無い（新規端末）。操作: handle。
## 期待: sign_up だけを呼び、成功したらトークンを保存する。
func test_new_device_calls_sign_up_and_saves_tokens() -> void:
	_repository.sign_up_results = [FakeAuthRepository.ok("a1", "r1")]
	var result := await _use_case.handle()
	assert_bool(result.ok).is_true()
	assert_array(_repository.calls).contains_exactly(["sign_up"])
	assert_str(_tokens.access).is_equal("a1")
	assert_str(_tokens.refresh).is_equal("r1")


## 前提: 保存トークンがある（既存端末）。操作: handle。
## 期待: sign_in だけを呼び、新しいトークンで保存し直す。
func test_existing_device_calls_sign_in() -> void:
	_tokens.save_tokens("old-a", "old-r")
	_repository.sign_in_results = [FakeAuthRepository.ok("a2", "r2")]
	var result := await _use_case.handle()
	assert_bool(result.ok).is_true()
	assert_array(_repository.calls).contains_exactly(["sign_in"])
	assert_str(_tokens.refresh).is_equal("r2")


## 前提: 保存トークンがあるが、サーバーが端末を知らない（sign_in が 10002）。操作: handle。
## 期待: sign_up に 1 回切り替えて成功する（端末がサーバー側で消えた場合の復旧）。
func test_sign_in_10002_switches_to_sign_up_once() -> void:
	_tokens.save_tokens("old-a", "old-r")
	_repository.sign_in_results = [FakeAuthRepository.business(10002)]
	_repository.sign_up_results = [FakeAuthRepository.ok("a3", "r3")]
	var result := await _use_case.handle()
	assert_bool(result.ok).is_true()
	assert_array(_repository.calls).contains_exactly(["sign_in", "sign_up"])
	assert_str(_tokens.access).is_equal("a3")


## 前提: 保存トークンが無いが、サーバーに端末が登録済み（sign_up が 10004）。操作: handle。
## 期待: sign_in に 1 回切り替えて成功する（トークンを失った端末が同じ利用者に戻れる。要件 F1）。
func test_sign_up_10004_switches_to_sign_in_once() -> void:
	_repository.sign_up_results = [FakeAuthRepository.business(10004)]
	_repository.sign_in_results = [FakeAuthRepository.ok("a4", "r4")]
	var result := await _use_case.handle()
	assert_bool(result.ok).is_true()
	assert_array(_repository.calls).contains_exactly(["sign_up", "sign_in"])
	assert_str(_tokens.refresh).is_equal("r4")


## 前提: sign_up が 10004、切り替えた sign_in が 10002（サーバーの状態が矛盾）。操作: handle。
## 期待: 切り替えは 1 回で打ち切り、sign_in の 299（10002）を BUSINESS で返す。トークンは保存しない。
## これが無いと sign_up と sign_in を無限に往復する。
func test_stops_after_one_switch() -> void:
	_repository.sign_up_results = [FakeAuthRepository.business(10004)]
	_repository.sign_in_results = [FakeAuthRepository.business(10002)]
	var result := await _use_case.handle()
	assert_bool(result.ok).is_false()
	assert_int(result.error.kind).is_equal(AppError.Kind.BUSINESS)
	assert_int(result.error.error_code).is_equal(10002)
	assert_array(_repository.calls).contains_exactly(["sign_up", "sign_in"])
	assert_str(_tokens.access).is_empty()


## 前提: sign_in が 10002 以外の業務エラー（例: 99999）。操作: handle。
## 期待: 切り替えず、そのエラーを返す。
func test_other_business_error_is_not_switched() -> void:
	_tokens.save_tokens("old-a", "old-r")
	_repository.sign_in_results = [FakeAuthRepository.business(99999)]
	var result := await _use_case.handle()
	assert_bool(result.ok).is_false()
	assert_int(result.error.error_code).is_equal(99999)
	assert_array(_repository.calls).contains_exactly(["sign_in"])


## 前提: sign_up が通信失敗（NETWORK）。操作: handle。
## 期待: 切り替えず NETWORK を返す（再試行は画面の操作。自動で繰り返さない）。
func test_network_error_is_returned_without_switch() -> void:
	var network := AuthSessionResult.new(null, AppError.new(AppError.Kind.NETWORK))
	_repository.sign_up_results = [network]
	var result := await _use_case.handle()
	assert_int(result.error.kind).is_equal(AppError.Kind.NETWORK)
	assert_array(_repository.calls).contains_exactly(["sign_up"])
