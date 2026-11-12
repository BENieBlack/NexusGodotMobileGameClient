## ApiClient から見た「マスターハッシュの供給」の契約（client_design.md 3-5 X-Master-Hash）。
##
## 目的: ApiClient（core）は master_data を参照できない。core がこの契約を定義し、
##       master_data の Repository が継承して実装し、AppContext が ApiClient に渡す。
## ApiClient の使い方: すべてのリクエストに、master_hash() が空でなければ X-Master-Hash を付ける。
##       サーバーはこれと最新のハッシュを比べ、違えば 200 応答に X-Master-Update-Required を付ける。
class_name MasterHashProvider
extends RefCounted


## 端末が持つマスターのハッシュ。まだ更新していない（初回）なら空文字。
func master_hash() -> String:
	push_error("未実装: MasterHashProvider.master_hash")
	return ""
