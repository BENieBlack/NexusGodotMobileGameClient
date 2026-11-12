## LoginUseCase の単体テスト。偽の login API で、結果の取り込み（player・ログインボーナス）、
## 失敗時に何も書き換えないこと、冪等キーの扱いを確かめる。
extends GdUnitTestSuite

var _login: FakeLoginRepositories.FakeLogin
var _bonuses: LocalLoginBonusRepository
var _player: LocalPlayerRepository
var _use_case: LoginUseCase


func before_test() -> void:
	_login = FakeLoginRepositories.FakeLogin.new()
	_bonuses = LocalLoginBonusRepository.new()
	_player = LocalPlayerRepository.new()
	_use_case = LoginUseCase.new(_login, _bonuses, ApplyLoginDataUseCase.new(_player))


## 前提: 成功の結果（プレイヤー・所持データ・ログインボーナス 1 件）。操作: handle("k")。
## 期待: player に反映され、ログインボーナスが login の Repository に入り、指定した冪等キーで送る。
func test_success_applies_player_and_bonuses() -> void:
	var bonus := LoginBonus.new("u", "gold", "gold", 100)
	var bonuses: Array[LoginBonus] = [bonus]
	_login.result = LoginDataResult.new(
		null, {"my_id": "abc"}, {"trx_wallet_list": [{"mst_item_id": "gold"}]}, bonuses
	)
	var result := await _use_case.handle("k")

	assert_bool(result.ok).is_true()
	assert_array(_login.keys).contains_exactly(["k"])
	assert_str(_player.current().user_id()).is_equal("abc")
	assert_int(_player.current().trx_list("trx_wallet_list").size()).is_equal(1)
	assert_int(_bonuses.list().size()).is_equal(1)


## 前提: 付与の無い日（ログインボーナスが空の成功）。期待: 前回の受取を残さず、空に置き換える。
func test_empty_bonus_replaces_previous() -> void:
	var old: Array[LoginBonus] = [LoginBonus.new("old")]
	_bonuses.replace(old)
	_login.result = LoginDataResult.new(null, {"my_id": "abc"})
	await _use_case.handle("k")
	assert_array(_bonuses.list()).is_empty()


## 前提: 失敗の結果（BUSINESS）。期待: その AppError を返し、player・ログインボーナスは書き換えない
## （失敗したのに古い状態を中途半端に壊さない。login が成功するまで先へ進ませない。D4）。
func test_failure_returns_error_and_keeps_state() -> void:
	var old: Array[LoginBonus] = [LoginBonus.new("old")]
	_bonuses.replace(old)
	var error := AppError.new(AppError.Kind.BUSINESS)
	error.error_code = 99999
	_login.result = LoginDataResult.new(error)

	var result := await _use_case.handle("k")

	assert_bool(result.ok).is_false()
	assert_int(result.error.error_code).is_equal(99999)
	assert_bool(_player.current().is_empty()).is_true()
	assert_int(_bonuses.list().size()).is_equal(1)


## 前提: 冪等キーを渡さない。期待: キー無しで送らず、新しく作った UUID を付ける（D6）。
func test_empty_key_is_generated() -> void:
	await _use_case.handle()
	assert_int(_login.keys.size()).is_equal(1)
	assert_str(_login.keys[0]).has_length(36)
