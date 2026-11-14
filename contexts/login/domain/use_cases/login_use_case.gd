## login（POST /auth/login）の UseCase（client_design.md 3-1・3-2 の LOGIN 段階、architecture.md 5 節 6）。
##
## 目的: 認証後に 1 回呼び、サーバーからプレイヤー・所持データ・ログインボーナスを取り、保持先へ反映する。
##       成功するまで規約・ログインボーナス・ホームへ進ませない（D4）。
## 流れ（handle）:
##   1. 冪等キーを決める（呼び出し元が渡す。空なら作る）。X-Unique-Request-Identifier に必ず付ける（D6）
##   2. LoginRepository.fetch_login で送る。失敗ならその AppError を返す（何も反映しない）
##   3. プレイヤーと所持データを、player の公開 UseCase（ApplyLoginDataUseCase）に渡す
##   4. ログインボーナスを自コンテキストの Repository に置く
## 冪等キーの扱い（client_design.md 3-4）: キーの寿命は「ひとつの操作」で、持つのは呼び出し元（presenter）。
##   失敗して再送するとき、IdempotencyKey.can_reuse(error.kind) が真なら同じキーを渡し、
##   偽（BUSINESS。業務エラーも保存され、同じエラーが返り続ける）なら IdempotencyKey.generate() で作り直す。
##   成功したら捨てる。
## 失敗の扱い: 例外にせず Result.failure(AppError) で返す。
class_name LoginUseCase
extends RefCounted

var _login_repository: LoginRepository
var _login_bonus_repository: LoginBonusRepository
var _apply_login_data: ApplyLoginDataUseCase


func _init(
	login_repository: LoginRepository,
	login_bonus_repository: LoginBonusRepository,
	apply_login_data: ApplyLoginDataUseCase
) -> void:
	_login_repository = login_repository
	_login_bonus_repository = login_bonus_repository
	_apply_login_data = apply_login_data


## login する。idempotency_key は呼び出し元が保持するキー。空のときは、キー無しで送って
## 二重送信の保護を失わないよう、ここで新しく作る（再利用はできないので、通常は渡すこと）。
func handle(idempotency_key: String = "") -> Result:
	# --- 1. 冪等キー ---
	var key := idempotency_key if idempotency_key != "" else IdempotencyKey.generate()

	# --- 2. 送信 ---
	var fetched := await _login_repository.fetch_login(key)
	if not fetched.ok:
		return Result.failure(fetched.error)

	# --- 3・4. 反映（成功したときだけ。失敗時に古い状態を中途半端に書き換えない） ---
	_apply_login_data.handle(
		fetched.sys_player,
		fetched.trx_lists,
		fetched.trx_diamond,
		fetched.server_time_offset_seconds,
		fetched.has_server_time
	)
	_login_bonus_repository.replace(fetched.login_bonuses)
	return Result.success()
