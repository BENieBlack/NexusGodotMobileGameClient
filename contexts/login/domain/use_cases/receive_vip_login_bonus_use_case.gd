## VIP ログインボーナスの再受け取りの UseCase（POST /login_bonus/receive。client_design.md 3-1〜3-4）。
##
## 流れ（handle）:
##   1. LoginBonusCalendarRepository.receive_vip(mst_vip_login_bonus_id, 冪等キー)。失敗なら何も反映せず返す
##   2. 成功なら、updated_resources を player の公開 UseCase（ApplyUpdatedResourcesUseCase）で所持数へ反映する
##   3. メモリの VIP の段を応答の vip_login_bonus_calendar に置き換える（サーバーの値を正とする。通常の段は変えない）。
##      応答の段が読めないときは、メモリの VIP の段を duplicate_as_re_received() した複製で代える
##      （その場合、報酬行は読めないので rewards は空になりうる。所持数は updated_resources で反映済み）
##   4. 結果（rewards・vip_calendar）を返す
## 冪等キー（3-4）: キーの寿命は「ひとつの操作」で、持つのは呼び出し元（presenter）。同じキーで再送してよいのは
##   応答が届かなかったとき（通信断・409・503）だけ。BUSINESS（26001〜26003 の 299）の後・成功の後は新しいキー
##   （IdempotencyKey.can_reuse が偽）。26001〜26003 はコードで分岐せず、画面が状態を取り直す。
## 失敗の扱い: 例外にせず、結果の ok・error で返す。
class_name ReceiveVipLoginBonusUseCase
extends RefCounted

var _calendar_repository: LoginBonusCalendarRepository
var _login_bonus_repository: LoginBonusRepository
var _apply_updated_resources: ApplyUpdatedResourcesUseCase


func _init(
	calendar_repository: LoginBonusCalendarRepository,
	login_bonus_repository: LoginBonusRepository,
	apply_updated_resources: ApplyUpdatedResourcesUseCase
) -> void:
	_calendar_repository = calendar_repository
	_login_bonus_repository = login_bonus_repository
	_apply_updated_resources = apply_updated_resources


func handle(mst_vip_login_bonus_id: String, idempotency_key: String) -> ReceiveVipLoginBonusResult:
	# --- 1. 送信 ---
	var result := await _calendar_repository.receive_vip(mst_vip_login_bonus_id, idempotency_key)
	if not result.ok:
		return result

	# --- 2. 所持数の反映（ホームが戻ったときに最新になる）---
	_apply_updated_resources.handle(result.updated_resources)

	# --- 3. メモリの VIP の段を置き換える ---
	var current := _login_bonus_repository.calendars()
	var vip_calendar := result.vip_calendar
	if vip_calendar == null and current.vip != null:
		vip_calendar = current.vip.duplicate_as_re_received()
	if vip_calendar != null:
		_login_bonus_repository.replace_calendars(
			LoginBonusCalendars.new(current.normal, vip_calendar)
		)
	result.vip_calendar = vip_calendar
	return result
