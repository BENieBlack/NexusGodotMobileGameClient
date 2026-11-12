## ApiClient から見た「認証トークンの供給」の契約（client_design.md 3-5、architecture.md 2-1）。
##
## 目的: ApiClient（core）は auth コンテキストを参照できない。そこで core がこの契約を定義し、
##       auth の data（local_auth_token_repository）が継承して実装し、AppContext が ApiClient に渡す。
## ApiClient の使い方:
##   - access_token()  : 認証付きリクエストの Authorization に付ける。空なら付けない
##   - refresh_token() : 401 のとき refresh_token API に送る。空ならログアウト扱い
##   - save_tokens()   : refresh 成功時に新しいトークンを保存する
## セッションの破棄は、この契約ではなく ApiClient の session_expired シグナル（EventBus 経由）で行う。
## 実装しないメソッドは push_error する（architecture.md 7 節の契約の書き方）。
class_name ApiAuthProvider
extends RefCounted


func access_token() -> String:
	push_error("未実装: ApiAuthProvider.access_token")
	return ""


func refresh_token() -> String:
	push_error("未実装: ApiAuthProvider.refresh_token")
	return ""


func save_tokens(_access_token: String, _refresh_token: String) -> void:
	push_error("未実装: ApiAuthProvider.save_tokens")
