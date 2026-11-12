## sign_up / sign_in で得た認証の結果（クライアント固有の状態の読み取りモデル）。
##
## 目的: AuthRepository が UseCase へ渡す値。UseCase はこのトークンを ApiAuthProvider 経由で保存する。
## 項目: access_token（JWT。API の Authorization に付ける）、refresh_token（401 のときの再発行に使う）。
## 注意: トークンは秘密情報。ログや print に出さない。
class_name AuthSession
extends RefCounted

var access_token: String = ""
var refresh_token: String = ""


func _init(p_access_token: String = "", p_refresh_token: String = "") -> void:
	access_token = p_access_token
	refresh_token = p_refresh_token
