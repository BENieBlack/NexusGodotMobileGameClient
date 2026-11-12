## login API の契約（architecture.md 7 節）。
##
## 目的: LoginUseCase が通信の実装を知らずに、テストでは偽物に差し替えられるようにする。
## 実装: contexts/login/data/repositories/login_api_repository.gd。
## 失敗は例外にせず、結果の error（AppError）で返す。
class_name LoginRepository
extends RefCounted


## POST /auth/login を送る。idempotency_key は冪等キー（必ず付けて送る。空にしない）。
func fetch_login(_idempotency_key: String) -> LoginDataResult:
	push_error("未実装: LoginRepository.fetch_login")
	return null
