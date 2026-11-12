## 認証 API（sign_up / sign_in）の契約（architecture.md 7 節）。
##
## 目的: AuthenticateUseCase が、署名・HTTP・device_id の保存を知らずに、テストでは偽物に差し替えられるようにする。
## 実装: contexts/auth/data/repositories/auth_api_repository.gd。
## 端末の device_id は実装が保存済みの値を使う（無ければ作る）ので、引数には取らない。
## 失敗は例外にせず、結果の error（AppError）で返す。
class_name AuthRepository
extends RefCounted


## 新規登録（POST /auth/sign_up。署名つき）。
func sign_up() -> AuthSessionResult:
	push_error("未実装: AuthRepository.sign_up")
	return null


## 既存端末のログイン（POST /auth/sign_in）。
func sign_in() -> AuthSessionResult:
	push_error("未実装: AuthRepository.sign_in")
	return null
