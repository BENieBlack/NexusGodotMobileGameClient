## LoginUseCase のテスト用の偽 Repository（API 側）。メモリのログインボーナス保持は本物を使う。
class_name FakeLoginRepositories
extends RefCounted


## 偽の login API。result を返し、渡された冪等キーを記録する。
class FakeLogin:
	extends LoginRepository
	var result: LoginDataResult = LoginDataResult.new()
	var keys: Array[String] = []

	func fetch_login(idempotency_key: String) -> LoginDataResult:
		keys.append(idempotency_key)
		return result
