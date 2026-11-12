## Reverb（WebSocket のリアルタイム通知）の接続先と、プライベートチャンネルの認証先（値だけを持つ）。
##
## 目的: Toast（core/presentation）は設定の読み出し（core/data の ApiConfig）を直接参照できない
##       （依存チェック P1）。そこで、ApiConfig が作り、AppContext → presenter → Toast へ渡す入れ物として置く。
## 持つ値:
##   ws_url   : WebSocket の接続先（例: ws://localhost:8080/app/nexus-local-key）
##   auth_url : private / presence チャンネルの認証 URL（例: http://localhost:8090/broadcasting/auth）。
##              Reverb のサーバー（WebSocket）ではなく、API サーバー側にある
class_name ReverbEndpoint
extends RefCounted

var ws_url: String
var auth_url: String


func _init(p_ws_url: String = "", p_auth_url: String = "") -> void:
	ws_url = p_ws_url
	auth_url = p_auth_url
