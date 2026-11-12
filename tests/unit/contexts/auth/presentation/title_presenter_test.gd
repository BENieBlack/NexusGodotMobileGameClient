## TitlePresenter（タイトル画面）の画面状態のテスト（client_design.md 1-2・3-2）。
##
## 偽の Repository を載せた本物の UseCase と、偽の遷移・通知を presenter に渡し、シーンを実際に生成して
## 段階（MASTER → AUTH → LOGIN → 完了）の進行、エラー表示と再試行（失敗した段階から）、冪等キーの扱いを確かめる。
## SceneRouter・Toast のオートロードは呼ばない（テスト中に本当に画面が切り替わらないように）。
extends GdUnitTestSuite

const TITLE_SCENE := "res://contexts/auth/presentation/title/title.tscn"
const STATUS_PATH := "CenterContainer/PanelContainer/VBoxContainer/StatusLabel"
const RETRY_PATH := "CenterContainer/PanelContainer/VBoxContainer/RetryButton"

var _remote: FakeMasterRepositories.FakeRemote
var _auth_repository: FakeAuthRepository
var _login: SequencedLogin
var _router: ScreenTestDoubles.FakeRouter
var _toast: ScreenTestDoubles.FakeToast
var _tokens: FakeApiClient.FakeAuth
var _title: TitlePresenter


## login API の偽物。results を先頭から消費し、渡された冪等キーを記録する。
class SequencedLogin:
	extends LoginRepository
	var results: Array[LoginDataResult] = []
	var keys: Array[String] = []

	func fetch_login(idempotency_key: String) -> LoginDataResult:
		keys.append(idempotency_key)
		if results.is_empty():
			return LoginDataResult.new(null, {"my_id": "p1"})
		return results.pop_front()


func before_test() -> void:
	_remote = FakeMasterRepositories.FakeRemote.new()
	_remote.version = FakeMasterRepositories.make_version(false)
	_auth_repository = FakeAuthRepository.new()
	_auth_repository.sign_up_results = [FakeAuthRepository.ok()]
	_login = SequencedLogin.new()
	_router = ScreenTestDoubles.FakeRouter.new()
	_toast = ScreenTestDoubles.FakeToast.new()
	_tokens = FakeApiClient.FakeAuth.new()


## 偽の依存でタイトルを作って画面に載せる（_ready で自動開始する）。待ち時間は 0 にする。
func _start_title(tokens: FakeApiClient.FakeAuth = null) -> void:
	if tokens == null:
		tokens = _tokens
	var players := LocalPlayerRepository.new()
	var apply := ApplyLoginDataUseCase.new(players)
	_title = load(TITLE_SCENE).instantiate()
	_title.start_delay_sec = 0.0
	_title.master_notice_sec = 0.0
	_title.success_hold_sec = 0.0
	_title.setup(
		CheckMasterDataUseCase.new(_remote, FakeMasterRepositories.FakeStorage.new()),
		AuthenticateUseCase.new(_auth_repository, tokens),
		LoginUseCase.new(_login, LocalLoginBonusRepository.new(), apply),
		GetPlayerIdUseCase.new(players),
		GetAccessTokenUseCase.new(tokens),
		_router,
		_toast
	)
	add_child(auto_free(_title))
	await get_tree().process_frame


func _status() -> String:
	return (_title.get_node(STATUS_PATH) as Label).text


func _retry() -> Button:
	return _title.get_node(RETRY_PATH) as Button


func _business_login(code: int) -> LoginDataResult:
	var error := AppError.new(AppError.Kind.BUSINESS)
	error.error_code = code
	return LoginDataResult.new(error)


func _failed_login(kind: AppError.Kind) -> LoginDataResult:
	return LoginDataResult.new(AppError.new(kind))


## 前提: すべて成功。操作: 起動。
## 期待: 「ログイン成功!」を出し、通知を始め（プレイヤー ID つき）、規約画面へ 1 回だけ進む。再試行ボタンは出ない。
func test_all_success_goes_to_agreement() -> void:
	await _start_title()
	assert_array(_router.calls).contains_exactly(["agreement"])
	assert_str(_status()).is_equal("ログイン成功!")
	assert_bool(_retry().visible).is_false()
	assert_array(_toast.reverb_connects).contains_exactly(["p1"])
	assert_int(_login.keys.size()).is_equal(1)


## 前提: 保存トークンあり（既存端末）。期待: 認証中の文言が「ログイン中...」になる前に sign_in が呼ばれる
## （新規は sign_up。出し分けの根拠が UseCase の判定と同じであること）。
func test_existing_device_uses_sign_in() -> void:
	_auth_repository.sign_up_results = []
	_auth_repository.sign_in_results = [FakeAuthRepository.ok()]
	await _start_title(FakeApiClient.FakeAuth.new("a", "r"))
	assert_array(_auth_repository.calls).contains_exactly(["sign_in"])
	assert_array(_router.calls).contains_exactly(["agreement"])


## 前提: マスターの確認が失敗（FAILED）。期待: 止めずに認証・login へ進み、通知（トースト）が出る。
## 保存済みのデータで続行する設計（D8）。
func test_master_failure_continues_with_notice() -> void:
	_remote.version = null
	_remote.version_error = AppError.new(AppError.Kind.NETWORK)
	await _start_title()
	assert_array(_toast.toasts).contains_exactly(["マスターデータ"])
	assert_array(_router.calls).contains_exactly(["agreement"])


## 前提: 認証が通信断（NETWORK）で失敗。期待: 進行を止め、エラー文と再試行ボタンを出す（login は呼ばない）。
## 操作: 再試行を押す。期待: 認証からやり直して成功し、先へ進む（マスターは成功済みなので繰り返さない）。
func test_auth_failure_shows_error_then_retry_resumes_from_auth() -> void:
	_auth_repository.sign_up_results = [
		AuthSessionResult.new(null, AppError.new(AppError.Kind.NETWORK)), FakeAuthRepository.ok()
	]
	await _start_title()
	assert_str(_status()).contains("通信できませんでした")
	assert_bool(_retry().visible).is_true()
	assert_bool(_retry().disabled).is_false()
	assert_int(_login.keys.size()).is_equal(0)
	assert_array(_router.calls).is_empty()

	_retry().pressed.emit()
	await get_tree().process_frame
	assert_array(_router.calls).contains_exactly(["agreement"])
	assert_int(_remote.fetch_count).is_equal(1)


## 前提: login が通信断（NETWORK）で失敗し、再試行で成功する。
## 期待: エラー表示 → 再試行は LOGIN 段階から（sign_up は 1 回のまま）、冪等キーは同じものを再送する。
func test_login_network_failure_retries_login_only_with_same_key() -> void:
	_login.results = [_failed_login(AppError.Kind.NETWORK)]
	await _start_title()
	assert_str(_status()).contains("通信できませんでした")
	assert_bool(_retry().visible).is_true()
	assert_array(_router.calls).is_empty()

	_retry().pressed.emit()
	await get_tree().process_frame
	assert_array(_router.calls).contains_exactly(["agreement"])
	assert_int(_auth_repository.calls.size()).is_equal(1)
	assert_int(_login.keys.size()).is_equal(2)
	assert_str(_login.keys[1]).is_equal(_login.keys[0])


## 前提: login が業務エラー（BUSINESS。サーバーに結果が保存される）。期待: 再試行では冪等キーを作り直す
## （同じキーで送ると同じエラーが返り続けるため。設計 3-4）。表示にはエラーコードが出る。
func test_login_business_error_retries_with_new_key() -> void:
	_login.results = [_business_login(20001)]
	await _start_title()
	assert_str(_status()).contains("コード: 20001")

	_retry().pressed.emit()
	await get_tree().process_frame
	assert_int(_login.keys.size()).is_equal(2)
	assert_str(_login.keys[1]).is_not_equal(_login.keys[0])
	assert_array(_router.calls).contains_exactly(["agreement"])


## 前提: login 中にセッションが失効（SESSION_EXPIRED）。期待: メッセージを出し、再試行は AUTH からやり直す
## （sign_up がもう 1 回呼ばれ、キーも作り直す）。
func test_session_expired_in_login_restarts_from_auth() -> void:
	_auth_repository.sign_up_results = [FakeAuthRepository.ok(), FakeAuthRepository.ok()]
	_login.results = [_failed_login(AppError.Kind.SESSION_EXPIRED)]
	await _start_title()
	assert_str(_status()).contains("最初からやり直します")

	# 本物では、セッション失効でトークンが破棄される（ClearAuthSessionUseCase）。それを再現する
	_tokens.save_tokens("", "")
	_retry().pressed.emit()
	await get_tree().process_frame
	assert_int(_auth_repository.calls.size()).is_equal(2)
	assert_str(_login.keys[1]).is_not_equal(_login.keys[0])
	assert_array(_router.calls).contains_exactly(["agreement"])


## 前提: マスターが FAILED のまま、login が失敗。操作: 再試行。
## 期待: LOGIN からではなく MASTER 段階から（version を取り直す）やり直す。初回は更新要求が来ず、
## ここが再取得の唯一の手段のため（設計 1-2）。
func test_retry_after_master_failure_restarts_from_master() -> void:
	_remote.version = null
	_remote.version_error = AppError.new(AppError.Kind.NETWORK)
	_login.results = [_failed_login(AppError.Kind.NETWORK)]
	# 認証は 1 回目で保存したトークンを使うので、MASTER から再開した 2 回目は sign_in になる
	_auth_repository.sign_in_results = [FakeAuthRepository.ok()]
	await _start_title()
	assert_int(_remote.fetch_count).is_equal(1)
	assert_bool(_retry().visible).is_true()

	_retry().pressed.emit()
	await get_tree().process_frame
	assert_int(_remote.fetch_count).is_equal(2)
	assert_array(_router.calls).contains_exactly(["agreement"])


## 前提: login が 429（retry_after = 30）。期待: 文言に秒数が入り、再試行ボタンは押せない
## （自動で再送せず、押せるようになるまで待たせる。設計 1-3）。
func test_rate_limited_disables_retry_button() -> void:
	var limited := AppError.new(AppError.Kind.RATE_LIMITED)
	limited.retry_after = 30
	_login.results = [LoginDataResult.new(limited)]
	await _start_title()
	assert_str(_status()).contains("あと約 30 秒後")
	assert_bool(_retry().visible).is_true()
	assert_bool(_retry().disabled).is_true()


## 前提: login が 503（メンテナンス）。期待: サーバーの title / message を出し、再試行はすぐ押せる。
func test_maintenance_shows_server_message() -> void:
	var error := AppError.new(AppError.Kind.MAINTENANCE)
	error.maintenance = {"title": "メンテ中", "message": "しばらくお待ちください", "end_at": null}
	_login.results = [LoginDataResult.new(error)]
	await _start_title()
	assert_str(_status()).contains("メンテ中")
	assert_str(_status()).contains("しばらくお待ちください")
	assert_bool(_retry().disabled).is_false()


## 前提: マスター確認が数フレーム保留中（偽の remote を遅らせる）の間に、画面がツリーから外れる（遷移の再現）。
## 操作: 保留が明けるまでフレームを進める。期待: await から戻った presenter は何も進めず（認証・login・遷移・
## 通知なし）、エラーも出ない。破棄済みの画面や router を触らないこと（レビュー指摘）。
func test_screen_removed_during_await_stops_quietly() -> void:
	_remote.delay_frames = 3
	await _start_title()
	remove_child(_title)
	for i in range(6):
		await get_tree().process_frame
	assert_array(_router.calls).is_empty()
	assert_array(_toast.reverb_connects).is_empty()
	assert_int(_auth_repository.calls.size()).is_equal(0)
	assert_int(_login.keys.size()).is_equal(0)
	_title.free()


## 前提: 同じく保留中に、画面そのものを解放する（queue_free）。期待: 保留が明けてもエラーにならない
## （解放後の再開で例外が出ない。進行も起きない）。
func test_screen_freed_during_await_is_safe() -> void:
	_remote.delay_frames = 3
	await _start_title()
	_title.queue_free()
	for i in range(6):
		await get_tree().process_frame
	assert_array(_router.calls).is_empty()
	assert_int(_auth_repository.calls.size()).is_equal(0)
