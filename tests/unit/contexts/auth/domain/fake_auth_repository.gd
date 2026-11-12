## AuthenticateUseCase のテスト用の偽 AuthRepository。
##
## 目的: sign_up / sign_in の結果を呼ばれた順に差し込み、呼ばれた順序（calls）を検証する。
## 使い方: sign_up_results / sign_in_results に AuthSessionResult を積む（先頭から消費する）。
##   積んだ分を超えて呼ばれたら、テストの想定外なので失敗（SERVER_ERROR）を返す。
class_name FakeAuthRepository
extends AuthRepository

var sign_up_results: Array[AuthSessionResult] = []
var sign_in_results: Array[AuthSessionResult] = []
## 呼ばれた API の順序（"sign_up" / "sign_in"）
var calls: Array[String] = []


func sign_up() -> AuthSessionResult:
	calls.append("sign_up")
	return _next(sign_up_results)


func sign_in() -> AuthSessionResult:
	calls.append("sign_in")
	return _next(sign_in_results)


func _next(queue: Array[AuthSessionResult]) -> AuthSessionResult:
	if queue.is_empty():
		return AuthSessionResult.new(null, AppError.new(AppError.Kind.SERVER_ERROR, "想定外の呼び出し"))
	return queue.pop_front()


## 成功の結果。
static func ok(access: String = "access", refresh: String = "refresh") -> AuthSessionResult:
	return AuthSessionResult.new(AuthSession.new(access, refresh))


## 業務エラー（HTTP 299）の失敗。
static func business(code: int) -> AuthSessionResult:
	var error := AppError.new(AppError.Kind.BUSINESS)
	error.error_code = code
	return AuthSessionResult.new(null, error)
