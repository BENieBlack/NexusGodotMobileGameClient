## PrepareLoginBonusMasterUseCase の結果。
##
## 項目:
##   masters       段のマスターの束（引けた段だけ非 null）
##   covers        進捗のある段のマスターが全部引けたか（偽なら、その段は出せない。2-4）
##   refetched     CheckMasterDataUseCase.handle() を実行したか（1 回だけ）
##   check_status  再取得を実行したときの CheckMasterDataResult.Status（実行していなければ -1）
## 画面（GetLoginBonusScreenUseCase）は、引けない段だけ出さず、出せる段が無いときだけ文字の画面にする（1-3 ④）。
class_name PrepareLoginBonusMasterResult
extends RefCounted

var masters: LoginBonusStageMasters = LoginBonusStageMasters.new()
var covers: bool = false
var refetched: bool = false
var check_status: int = -1


func _init(
	p_masters: LoginBonusStageMasters = null,
	p_covers: bool = false,
	p_refetched: bool = false,
	p_check_status: int = -1
) -> void:
	if p_masters != null:
		masters = p_masters
	covers = p_covers
	refetched = p_refetched
	check_status = p_check_status
