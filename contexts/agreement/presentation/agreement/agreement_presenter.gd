## 利用規約同意画面の presenter（client_design.md 1-2・3-1・3-4）。
##
## 目的: 未同意の規約があるときだけ画面を見せ、「すべての規約に同意して続ける」で同意を送る。
##       未同意が無ければ画面を見せずにログインボーナスへ進む。失敗はスキップせず、エラー文と
##       「再試行」を出して止める（仮置き。設計 8 節 2）。
## 流れ:
##   1. 読み込み: 「読み込み中...」を出して未同意の規約を取得する（fetch_pending_agreements_use_case）
##      - 空 → そのままログインボーナスへ（画面は見えない）
##      - 一覧 → 規約カードと同意ボタンを出す
##      - 失敗 → エラー文と再試行（再試行は取得から）。SESSION_EXPIRED はタイトルへ戻る
##   2. 同意: ボタンを無効にし「送信中...」。規約ごとに 1 件ずつ直列に送る（consent_agreement_use_case）
##      - 成功 → 次の規約へ。全件終わったらログインボーナスへ
##      - 24001 で一覧が古い → UseCase が取り直した一覧に差し替え、最初から送り直す
##      - 失敗 → エラー文と再試行（再試行は失敗した規約から。成功済みの規約は送り直さない）
## 冪等キー（設計 3-4）: 規約ごとに 1 つ作って _consent_keys に持つ。再送してよい失敗（通信断・409・503 など）は
##   同じキーで送り直し、BUSINESS（業務エラーも保存される）は作り直す。成功した規約のキーは捨てる。
## 二重送信の防止: 送信中は _is_sending を立て、ボタンを無効にする（連打しても 2 回目は送らない）。
## 画面の破棄: await から戻ったとき、遷移・破棄済み（ツリーの外）なら何もせず終わる（破棄済みの画面や
##   router を触らない）。送信中だった場合は _is_sending を戻してから終わる。
## 依存: UseCase だけを呼ぶ。遷移は既定ではオートロードの SceneRouter（テストは setup で偽物を渡す）。
class_name AgreementPresenter
extends Control

## 失敗がどこで起きたか。再試行の起点を決める
enum Failed { NONE, FETCH, CONSENT }

## エラー文（SESSION_EXPIRED）を見せてからタイトルへ戻るまでの秒数
var session_notice_sec: float = 2.0

var _pending: Array[SysAgreement] = []
var _consent_index: int = 0
var _consent_keys: Dictionary = {}
var _failed: Failed = Failed.NONE
var _is_sending: bool = false

var _fetch_pending: FetchPendingAgreementsUseCase
var _consent: ConsentAgreementUseCase
var _router: Object
var _is_configured: bool = false

@onready var _agreement_list: VBoxContainer = $VBoxContainer/ScrollContainer/AgreementList
@onready var _agree_all_button: Button = $VBoxContainer/AgreeAllButton
@onready var _status_label: Label = $VBoxContainer/StatusLabel
@onready var _retry_button: Button = $VBoxContainer/RetryButton


## UseCase と遷移の相手を渡す。_ready より前に呼ぶとその値を使い、呼ばなければ _ready がオートロードから取る。
func setup(
	fetch_pending: FetchPendingAgreementsUseCase, consent: ConsentAgreementUseCase, router: Object
) -> void:
	_fetch_pending = fetch_pending
	_consent = consent
	_router = router
	_is_configured = true


func _ready() -> void:
	if not _is_configured:
		setup(
			AppContext.fetch_pending_agreements_use_case(),
			AppContext.consent_agreement_use_case(),
			SceneRouter
		)
	_agree_all_button.pressed.connect(_on_agree_all_pressed)
	_retry_button.pressed.connect(_on_retry_pressed)
	_agree_all_button.visible = false
	ErrorView.hide_retry(_retry_button)
	await _load()


## 未同意の規約を取得して、画面の状態（空・一覧・エラー）を決める。
func _load() -> void:
	ErrorView.hide_retry(_retry_button)
	_agree_all_button.visible = false
	_status_label.text = "読み込み中..."

	var result := await _fetch_pending.handle()
	if not is_inside_tree():
		return
	if not result.ok:
		await _fail(Failed.FETCH, result.error)
		return

	# 未同意が無ければ画面を見せずに進む（要件: 無ければ見えない）
	if result.agreements.is_empty():
		_router.goto_login_bonus()
		return
	_show_list(result.agreements)


## 規約の一覧を表示する（カードを作り直す）。
func _show_list(agreements: Array[SysAgreement]) -> void:
	_pending = agreements
	_consent_index = 0
	for child in _agreement_list.get_children():
		child.queue_free()
	for agreement in _pending:
		_add_agreement_card(agreement)
	_status_label.text = ""
	_agree_all_button.visible = true
	_agree_all_button.disabled = false


## 規約カード（タイトル + 版 + 「確認する」ボタン）を一覧に足す。
func _add_agreement_card(agreement: SysAgreement) -> void:
	var card := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = agreement.title + " v" + agreement.version
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(name_label)

	var open_button := Button.new()
	open_button.text = "確認する"
	open_button.pressed.connect(func() -> void: OS.shell_open(agreement.url))
	card.add_child(open_button)

	_agreement_list.add_child(card)


## 「すべての規約に同意して続ける」。連打されても送信は 1 本だけ。
func _on_agree_all_pressed() -> void:
	if _is_sending:
		return
	_consent_index = 0
	await _send_consents()


## 再試行ボタン。失敗した起点（取得 / 同意）からやり直す。
func _on_retry_pressed() -> void:
	ErrorView.hide_retry(_retry_button)
	if _failed == Failed.FETCH:
		await _load()
	else:
		await _send_consents()


## 未送信の規約を、_consent_index から順に 1 件ずつ送る。全件終わったらログインボーナスへ進む。
func _send_consents() -> void:
	if _is_sending:
		return
	_is_sending = true
	_agree_all_button.disabled = true
	_status_label.text = "送信中..."

	while _consent_index < _pending.size():
		var agreement := _pending[_consent_index]
		# 規約ごとに冪等キーを 1 つ持つ。無ければ作り、失敗後の再送では残っているものを使う
		var key: String = _consent_keys.get(agreement.sys_agreement_id, "")
		if key == "":
			key = IdempotencyKey.generate()
			_consent_keys[agreement.sys_agreement_id] = key

		var result := await _consent.handle(agreement.sys_agreement_id, key)
		if not is_inside_tree():
			_is_sending = false
			return
		if not result.ok:
			# 業務エラーはサーバーに保存されるので、再送ではキーを作り直す
			if not IdempotencyKey.can_reuse(result.error.kind):
				_consent_keys.erase(agreement.sys_agreement_id)
			_is_sending = false
			await _fail(Failed.CONSENT, result.error)
			return

		_consent_keys.erase(agreement.sys_agreement_id)
		if result.refetched:
			# 24001: 一覧が古かった。取り直した一覧に差し替えて、最初から送る
			if result.agreements.is_empty():
				break
			_show_list(result.agreements)
			_agree_all_button.disabled = true
			_status_label.text = "送信中..."
			continue
		_consent_index += 1

	_is_sending = false
	_router.goto_login_bonus()


## 失敗を表示して止まる。SESSION_EXPIRED は、メッセージを見せてタイトルへ戻る（最初からやり直す）。
func _fail(origin: Failed, error: AppError) -> void:
	_failed = origin
	if error.kind == AppError.Kind.SESSION_EXPIRED:
		# 規約の同意状態はサーバーにあるので、冪等キーは作り直す。タイトルへ戻れば画面ごと新しくなる
		_consent_keys.clear()
		_status_label.text = ErrorMessages.text(error)
		if session_notice_sec > 0.0:
			await get_tree().create_timer(session_notice_sec).timeout
			if not is_inside_tree():
				return
		_router.goto_title()
		return
	# 同意ボタンは隠し、再試行ボタンだけを見せる（再試行が送信を再開する）
	_agree_all_button.visible = false
	await ErrorView.show_error(_status_label, _retry_button, error)
