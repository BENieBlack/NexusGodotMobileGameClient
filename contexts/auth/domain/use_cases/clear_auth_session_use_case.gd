## 認証セッションを破棄する UseCase（client_design.md 2-1、architecture.md 5 節 8）。
##
## 目的: refresh に失敗してセッションが無効になったとき（EventBus.session_expired。AppContext が受け手として
##       登録する）、保存しているトークンを空にして「次は sign_up / sign_in からやり直す」状態にする。
## 消すもの: アクセストークンとリフレッシュトークン。device_id は端末の識別なので消さない
##           （消すと別の端末として sign_up され、同じ利用者に戻れなくなる）。
## 実装の方法: ApiAuthProvider.save_tokens に空文字を渡す（空 = 保存なし。別の契約を増やさない）。
class_name ClearAuthSessionUseCase
extends RefCounted

var _token_store: ApiAuthProvider


func _init(token_store: ApiAuthProvider) -> void:
	_token_store = token_store


## トークンを破棄する。
func handle() -> Result:
	_token_store.save_tokens("", "")
	return Result.success()
