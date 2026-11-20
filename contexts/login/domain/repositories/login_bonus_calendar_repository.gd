## ログインボーナスのカレンダー API（list・receive）の契約（architecture.md 7 節）。
##
## 目的: UseCase が通信の実装を知らずに、テストでは偽物に差し替えられるようにする。
## 実装: contexts/login/data/repositories/login_bonus_calendar_api_repository.gd。
## 命名は login_repository / login_api_repository の対に倣う（契約は <名前>_repository、実装は <名前>_api_repository）。
## 失敗は例外にせず、結果の error（AppError）で返す。
class_name LoginBonusCalendarRepository
extends RefCounted


## POST /login_bonus/list（本文なし）。list 系なので冪等キーは付けない（サーバーは同じキーの応答を 24 時間
## 再生し、古い状態が返るため）。
func fetch_calendars() -> FetchLoginBonusCalendarsResult:
	push_error("未実装: LoginBonusCalendarRepository.fetch_calendars")
	return null


## POST /login_bonus/receive（本文 mst_vip_login_bonus_id）。idempotency_key は必ず付ける（空にしない）。
## 同じキーで再送してよいのは応答が届かなかったとき（通信断・409・503）だけ。業務エラー（299）の後は新しいキー。
func receive_vip(
	_mst_vip_login_bonus_id: String, _idempotency_key: String
) -> ReceiveVipLoginBonusResult:
	push_error("未実装: LoginBonusCalendarRepository.receive_vip")
	return null
