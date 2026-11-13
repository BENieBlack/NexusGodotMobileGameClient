## AgreementPresenter（規約画面）の画面状態のテスト（client_design.md 1-2・3-4）。
##
## 偽の AgreementRepository を載せた本物の UseCase と偽の遷移を渡し、シーンを生成して、
## 空ならスキップ・一覧表示・規約ごとの同意と冪等キー・失敗の再試行（失敗した規約から）・
## 24001 の取り直し・SESSION_EXPIRED でタイトルへ戻る・二重送信の防止を確かめる。
extends GdUnitTestSuite

const AGREEMENT_SCENE := "res://contexts/agreement/presentation/agreement/agreement.tscn"
const LIST_PATH := "VBoxContainer/ScrollContainer/AgreementList"
const AGREE_PATH := "VBoxContainer/AgreeAllButton"
const RETRY_PATH := "VBoxContainer/RetryButton"
const STATUS_PATH := "VBoxContainer/StatusLabel"

var _repository: FakeAgreementRepository
var _document_repository: FakeAgreementDocumentRepository
var _router: ScreenTestDoubles.FakeRouter
var _screen: AgreementPresenter


## consent を 1 フレーム待たせる偽物（送信中に 2 回目のクリックが来る状況を再現する）。
class SlowAgreementRepository:
	extends FakeAgreementRepository

	func consent(sys_agreement_id: int, idempotency_key: String) -> Result:
		await Engine.get_main_loop().process_frame
		return await super(sys_agreement_id, idempotency_key)


## fetch_pending を 1 フレーム待たせる偽物（取得の保留中に画面が外れる状況を再現する）。
class SlowFetchRepository:
	extends FakeAgreementRepository

	func fetch_pending() -> PendingAgreementsResult:
		# _start が 1 フレーム進めるので、それより長く（3 フレーム）保留する
		for i in range(3):
			await Engine.get_main_loop().process_frame
		return await super()


func before_test() -> void:
	_repository = FakeAgreementRepository.new()
	_document_repository = FakeAgreementDocumentRepository.new()
	_router = ScreenTestDoubles.FakeRouter.new()


## 偽の依存で規約画面を作って載せる（_ready で取得を始める）。
func _start(repository: FakeAgreementRepository = null) -> void:
	if repository != null:
		_repository = repository
	_screen = load(AGREEMENT_SCENE).instantiate()
	_screen.session_notice_sec = 0.0
	_screen.setup(
		FetchPendingAgreementsUseCase.new(_repository),
		ConsentAgreementUseCase.new(_repository),
		_router,
		FetchAgreementDocumentUseCase.new(_document_repository)
	)
	add_child(auto_free(_screen))
	await get_tree().process_frame


func _agree() -> Button:
	return _screen.get_node(AGREE_PATH) as Button


func _retry() -> Button:
	return _screen.get_node(RETRY_PATH) as Button


func _status() -> String:
	return (_screen.get_node(STATUS_PATH) as Label).text


func _card_count() -> int:
	return (_screen.get_node(LIST_PATH) as VBoxContainer).get_child_count()


func _failure(kind: AppError.Kind) -> Result:
	return Result.failure(AppError.new(kind))


## 前提: 未同意が無い（空）。期待: 画面を見せず、そのままログインボーナスへ（同意ボタンは出ない）。
func test_empty_skips_to_login_bonus() -> void:
	_repository.pending_results = [FakeAgreementRepository.pending_ok([])]
	await _start()
	assert_array(_router.calls).contains_exactly(["login_bonus"])
	assert_bool(_agree().visible).is_false()


## 前提: 未同意が 2 件。期待: カードが 2 枚と同意ボタンが出る（まだ遷移しない）。
## 操作: 同意ボタン。期待: 規約ごとに 1 件ずつ（別々の冪等キーで）送り、全件終わったらログインボーナスへ。
func test_list_then_consent_each_with_own_key() -> void:
	_repository.pending_results = [FakeAgreementRepository.pending_ok([1, 2])]
	_repository.consent_results = [Result.success(), Result.success()]
	await _start()
	assert_int(_card_count()).is_equal(2)
	assert_bool(_agree().visible).is_true()
	assert_array(_router.calls).is_empty()

	_agree().pressed.emit()
	await get_tree().process_frame
	assert_array(_repository.calls).contains_exactly(["pending", "consent:1", "consent:2"])
	assert_str(_repository.keys[0]).is_not_equal(_repository.keys[1])
	assert_array(_router.calls).contains_exactly(["login_bonus"])


## 前提: 取得が通信断で失敗。期待: エラー文と再試行ボタン（スキップしない）。
## 操作: 再試行。期待: 取得からやり直し、一覧が出る。
func test_fetch_failure_shows_error_and_retry_refetches() -> void:
	_repository.pending_results = [
		FakeAgreementRepository.pending_failure(AppError.Kind.NETWORK),
		FakeAgreementRepository.pending_ok([1]),
	]
	await _start()
	assert_str(_status()).contains("通信できませんでした")
	assert_bool(_retry().visible).is_true()
	assert_array(_router.calls).is_empty()

	_retry().pressed.emit()
	await get_tree().process_frame
	assert_int(_card_count()).is_equal(1)
	assert_bool(_agree().visible).is_true()
	assert_bool(_retry().visible).is_false()


## 前提: 2 件のうち 2 件目の同意が通信断で失敗。期待: エラーと再試行。再試行は失敗した規約（2 件目）から、
## 同じ冪等キーで送る（成功済みの 1 件目は送り直さない。通信断は処理済みかもしれないため再利用）。
func test_consent_failure_retries_from_failed_agreement_with_same_key() -> void:
	_repository.pending_results = [FakeAgreementRepository.pending_ok([1, 2])]
	_repository.consent_results = [
		Result.success(), _failure(AppError.Kind.NETWORK), Result.success()
	]
	await _start()
	_agree().pressed.emit()
	await get_tree().process_frame
	assert_bool(_retry().visible).is_true()
	assert_array(_router.calls).is_empty()

	_retry().pressed.emit()
	await get_tree().process_frame
	assert_array(_repository.calls).contains_exactly(
		["pending", "consent:1", "consent:2", "consent:2"]
	)
	assert_str(_repository.keys[2]).is_equal(_repository.keys[1])
	assert_array(_router.calls).contains_exactly(["login_bonus"])


## 前提: 同意が業務エラー（BUSINESS。結果がサーバーに保存される）で失敗。
## 期待: 再試行では冪等キーを作り直す（同じキーだと同じエラーが返り続けるため）。
func test_consent_business_error_retries_with_new_key() -> void:
	_repository.pending_results = [FakeAgreementRepository.pending_ok([1])]
	_repository.consent_results = [FakeAgreementRepository.business(24999), Result.success()]
	await _start()
	_agree().pressed.emit()
	await get_tree().process_frame
	assert_str(_status()).contains("コード: 24999")

	_retry().pressed.emit()
	await get_tree().process_frame
	assert_str(_repository.keys[1]).is_not_equal(_repository.keys[0])
	assert_array(_router.calls).contains_exactly(["login_bonus"])


## 前提: 1 件目の同意が 24001（一覧が古い）。UseCase が取り直した一覧は 2 だけ。
## 期待: 一覧を差し替え、取り直した規約（2）を送って進む（画面に出さずに処理する）。
func test_consent_24001_refetches_and_continues_with_new_list() -> void:
	_repository.pending_results = [
		FakeAgreementRepository.pending_ok([1]), FakeAgreementRepository.pending_ok([2])
	]
	_repository.consent_results = [FakeAgreementRepository.business(24001), Result.success()]
	await _start()
	_agree().pressed.emit()
	await get_tree().process_frame
	assert_array(_repository.calls).contains_exactly(
		["pending", "consent:1", "pending", "consent:2"]
	)
	assert_array(_router.calls).contains_exactly(["login_bonus"])


## 前提: 取得中にセッション失効（SESSION_EXPIRED）。期待: メッセージを出し、タイトルへ戻る
## （規約画面で起きたときは最初からやり直す。設計 1-3）。
func test_session_expired_goes_back_to_title() -> void:
	_repository.pending_results = [
		FakeAgreementRepository.pending_failure(AppError.Kind.SESSION_EXPIRED)
	]
	await _start()
	await get_tree().process_frame
	assert_str(_status()).contains("最初からやり直します")
	assert_array(_router.calls).contains_exactly(["title"])


## 前提: 送信が 1 フレーム遅い偽物（送信中）。操作: 同意ボタンを 2 回続けて押す。
## 期待: 送信は 1 本だけ（ボタンが無効になり、2 回目は無視される。ケース 15）。
func test_double_press_sends_once() -> void:
	var slow := SlowAgreementRepository.new()
	slow.pending_results = [FakeAgreementRepository.pending_ok([1])]
	slow.consent_results = [Result.success(), Result.success()]
	await _start(slow)

	_agree().pressed.emit()
	_agree().pressed.emit()
	assert_bool(_agree().disabled).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(slow.calls).contains_exactly(["pending", "consent:1"])
	assert_array(_router.calls).contains_exactly(["login_bonus"])


## 前提: 取得の保留中に、画面がツリーから外れる（遷移の再現）。操作: 保留が明けるまで進める。
## 期待: await から戻った presenter は何もせず（遷移・カード作成なし）、エラーも出ない。
func test_screen_removed_during_fetch_stops_quietly() -> void:
	var slow := SlowFetchRepository.new()
	slow.pending_results = [FakeAgreementRepository.pending_ok([])]
	await _start(slow)
	remove_child(_screen)
	for i in range(4):
		await get_tree().process_frame
	assert_array(_router.calls).is_empty()
	_screen.free()


## 前提: 同意の送信中（1 フレーム遅い偽物）に、画面がツリーから外れる。
## 期待: 保留が明けても次の規約・遷移へ進まず、エラーも出ない。
func test_screen_removed_during_consent_stops_quietly() -> void:
	var slow := SlowAgreementRepository.new()
	slow.pending_results = [FakeAgreementRepository.pending_ok([1, 2])]
	slow.consent_results = [Result.success(), Result.success()]
	await _start(slow)
	_agree().pressed.emit()
	remove_child(_screen)
	for i in range(6):
		await get_tree().process_frame
	assert_array(_router.calls).is_empty()
	assert_array(slow.calls).contains_exactly(["pending", "consent:1"])
	_screen.free()


## 前提: 未同意が 1 件（URL あり）、本文の取得は成功する。
## 操作: 「確認する」。期待: 規約画面の上に閲覧画面が開き（遷移はしない）、規約の URL で本文を取得し、
## 表示名は「タイトル v版」。連打しても 2 枚目は開かない。操作: 閉じる。期待: 閲覧画面が消えて規約画面に戻り、
## もう一度開ける。
func test_open_button_opens_terms_viewer_and_close_returns() -> void:
	var pending := FakeAgreementRepository.pending_ok([1])
	pending.agreements[0].url = "/legal/a.html"
	_repository.pending_results = [pending]
	_document_repository.results = [
		FakeAgreementDocumentRepository.ok("<p>本文</p>"),
		FakeAgreementDocumentRepository.ok("<p>本文</p>"),
	]
	await _start()
	var card := (_screen.get_node(LIST_PATH) as VBoxContainer).get_child(0)
	var open_button := card.get_node("OpenButton") as Button

	open_button.pressed.emit()
	open_button.pressed.emit()
	await get_tree().process_frame
	var viewer := _screen.get_node("TermsViewer") as TermsViewerPresenter
	assert_object(viewer).is_not_null()
	assert_array(_document_repository.urls).contains_exactly(["/legal/a.html"])
	assert_str((viewer.get_node("VBoxContainer/TitleLabel") as Label).text).is_equal("規約1 v1.0")
	assert_array(_router.calls).is_empty()

	(viewer.get_node("VBoxContainer/CloseButton") as Button).pressed.emit()
	await get_tree().process_frame
	assert_bool(is_instance_valid(viewer)).is_false()
	assert_bool(_agree().visible).is_true()

	open_button.pressed.emit()
	await get_tree().process_frame
	assert_array(_document_repository.urls).has_size(2)
