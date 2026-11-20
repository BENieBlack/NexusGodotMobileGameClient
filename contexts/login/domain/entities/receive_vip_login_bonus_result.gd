## POST /login_bonus/receive（VIP の再受け取り）の結果。
##
## 項目（成功のとき）:
##   rewards            今回配った報酬（応答の login_bonus_list。login と同形）。無い・null は空
##   vip_calendar       応答の vip_login_bonus_calendar（is_granted_now 真・can_re_receive 偽）。
##                      段として読めなければ null。UseCase が成功を処理するとき、代替の段（メモリの VIP を
##                      duplicate_as_re_received したもの）に差し替える。それも無ければ null のまま
##   updated_resources  応答の updated_resources（辞書のまま。ApplyUpdatedResourcesUseCase への入力）。無い・null は {}
## 失敗は error（AppError）。BUSINESS（26001〜26003）は画面が状態を取り直す（コードで分岐しない）。
class_name ReceiveVipLoginBonusResult
extends Result

var rewards: Array[LoginBonus] = []
var vip_calendar: LoginBonusCalendar = null
var updated_resources: Dictionary = {}


func _init(
	p_error: AppError = null,
	p_rewards: Array[LoginBonus] = [],
	p_vip_calendar: LoginBonusCalendar = null,
	p_updated_resources: Dictionary = {}
) -> void:
	super(p_error == null, p_error)
	rewards = p_rewards
	vip_calendar = p_vip_calendar
	updated_resources = p_updated_resources
