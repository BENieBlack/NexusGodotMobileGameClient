## 保存中のアクセストークンを返す UseCase。
##
## 目的: タイトルの完了時に、リアルタイム通知（Reverb）の認証へ渡すトークンを取り出す。
##       presenter が保存の実装（data）を直接触らないための窓口。
## 注意: 返すのは文字列で、画面やログに出さない。トークンが無ければ空文字。
class_name GetAccessTokenUseCase
extends RefCounted

var _token_store: ApiAuthProvider


func _init(token_store: ApiAuthProvider) -> void:
	_token_store = token_store


## アクセストークンを返す（無ければ空文字）。
func handle() -> String:
	return _token_store.access_token()
