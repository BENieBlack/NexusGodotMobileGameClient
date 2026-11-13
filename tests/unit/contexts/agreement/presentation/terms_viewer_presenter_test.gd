## TermsViewerPresenter（規約の閲覧画面）の画面状態のテスト。
##
## 偽の AgreementDocumentRepository を載せた本物の UseCase を渡し、シーンを生成して、
## 読み込み中 → 表示、失敗 → 再試行 → 成功、「ブラウザで開く」、リンクの許可、二重取得の防止、
## 破棄後の await で例外を出さないことを確かめる。外部ブラウザは記録する偽物（opened）に差し替える。
extends GdUnitTestSuite

const VIEWER_SCENE := "res://contexts/agreement/presentation/terms_viewer/terms_viewer.tscn"
const URL := "/legal/terms-of-service-1.0.0.html"

var _repository: FakeAgreementDocumentRepository
var _viewer: TermsViewerPresenter
var _opened: Array[String] = []


func before_test() -> void:
	_repository = FakeAgreementDocumentRepository.new()
	_opened = []


## 偽の依存で閲覧画面を作って載せる（_ready で取得を始める）。1 フレーム進めて返す。
func _start() -> void:
	_viewer = load(VIEWER_SCENE).instantiate()
	_viewer.setup(
		FetchAgreementDocumentUseCase.new(_repository),
		"利用規約 v1.0.0",
		URL,
		func(url: String) -> void: _opened.append(url)
	)
	add_child(auto_free(_viewer))
	await get_tree().process_frame


func _status() -> Label:
	return _viewer.get_node("VBoxContainer/StatusLabel") as Label


func _body() -> RichTextLabel:
	return _viewer.get_node("VBoxContainer/BodyLabel") as RichTextLabel


func _retry() -> Button:
	return _viewer.get_node("VBoxContainer/RetryButton") as Button


func _browser() -> Button:
	return _viewer.get_node("VBoxContainer/BrowserButton") as Button


## 前提: 取得に 3 フレームかかる。期待: その間は「読み込み中...」で本文は空、ボタンは「閉じる」だけ。
## 取得が終わると状態表示が消え、HTML が BBCode にされて本文に出る（タイトルは規約名）。
func test_loading_then_shown() -> void:
	_repository.wait_frames = 3
	_repository.results = [FakeAgreementDocumentRepository.ok("<h1>見出し</h1><p>本文 [x]</p>")]
	await _start()
	assert_str(_status().text).is_equal("読み込み中...")
	assert_str(_body().text).is_equal("")
	assert_bool(_retry().visible).is_false()
	assert_bool(_browser().visible).is_false()

	for i in range(4):
		await get_tree().process_frame
	assert_str(_status().text).is_equal("")
	assert_str(_body().text).contains("[font_size=44][b]見出し[/b][/font_size]")
	assert_str(_body().get_parsed_text()).contains("本文 [x]")
	assert_str((_viewer.get_node("VBoxContainer/TitleLabel") as Label).text).is_equal("利用規約 v1.0.0")
	assert_array(_repository.urls).contains_exactly([URL])


## 前提: 1 回目が通信断。期待: エラー文と「再試行」「ブラウザで開く」。
## 操作: 再試行（2 回目は成功）。期待: 同じ URL で取り直し、本文が出てボタンは隠れる。
func test_failure_then_retry_succeeds() -> void:
	_repository.results = [
		FakeAgreementDocumentRepository.failure(AppError.Kind.NETWORK),
		FakeAgreementDocumentRepository.ok("<p>本文</p>"),
	]
	await _start()
	assert_str(_status().text).contains("通信できませんでした")
	assert_bool(_retry().visible).is_true()
	assert_bool(_browser().visible).is_true()

	_retry().pressed.emit()
	await get_tree().process_frame
	assert_array(_repository.urls).contains_exactly([URL, URL])
	assert_str(_status().text).is_equal("")
	assert_bool(_retry().visible).is_false()
	assert_bool(_browser().visible).is_false()
	assert_str(_body().get_parsed_text()).contains("本文")


## 前提: 取得が失敗。操作: 「ブラウザで開く」。期待: 元の URL（解決前のもの）で外部ブラウザを開く。
func test_open_in_browser_uses_original_url() -> void:
	_repository.results = [FakeAgreementDocumentRepository.failure(AppError.Kind.SERVER_ERROR)]
	await _start()
	_browser().pressed.emit()
	assert_array(_opened).contains_exactly([URL])


## 前提: 取得は成功したが、表示できる内容が無い（許可しないタグだけ）。期待: 空の画面を成功にせずエラーにする。
func test_unreadable_content_is_an_error() -> void:
	_repository.results = [FakeAgreementDocumentRepository.ok("<script>x</script>")]
	await _start()
	assert_str(_status().text).is_equal(TermsViewerPresenter.CONTENT_UNREADABLE_MESSAGE)
	assert_bool(_retry().visible).is_true()


## 前提: 取得中に再試行が押される状況（取得の保留中）。期待: 取得は 1 回だけ。
func test_no_double_fetch_while_loading() -> void:
	_repository.wait_frames = 3
	_repository.results = [FakeAgreementDocumentRepository.ok("<p>a</p>")]
	await _start()
	_retry().pressed.emit()
	for i in range(5):
		await get_tree().process_frame
	assert_array(_repository.urls).has_size(1)


## 期待: リンクは http / https だけ外部ブラウザで開く。javascript: や file: は無視する。
func test_links_only_http_and_https() -> void:
	_repository.results = [FakeAgreementDocumentRepository.ok("<p>a</p>")]
	await _start()
	_body().meta_clicked.emit("https://example.com/privacy")
	_body().meta_clicked.emit("HTTP://example.com/x")
	_body().meta_clicked.emit("javascript:alert(1)")
	_body().meta_clicked.emit("file:///etc/passwd")
	_body().meta_clicked.emit("/relative")
	assert_array(_opened).contains_exactly(["https://example.com/privacy", "HTTP://example.com/x"])


## 操作: 「閉じる」。期待: closed を出して画面が消える。
func test_close_emits_closed_and_frees() -> void:
	_repository.results = [FakeAgreementDocumentRepository.ok("<p>a</p>")]
	await _start()
	var closed_count := [0]
	_viewer.closed.connect(func() -> void: closed_count[0] += 1)
	(_viewer.get_node("VBoxContainer/CloseButton") as Button).pressed.emit()
	assert_int(closed_count[0]).is_equal(1)
	await get_tree().process_frame
	assert_bool(is_instance_valid(_viewer)).is_false()


## 前提: 取得の保留中に画面が破棄される。期待: 取得が返っても例外を出さず、止まらない（次の画面は取得できる）。
func test_freed_while_loading_does_not_crash() -> void:
	_repository.wait_frames = 3
	_repository.results = [FakeAgreementDocumentRepository.ok("<p>a</p>")]
	await _start()
	_viewer.queue_free()
	for i in range(5):
		await get_tree().process_frame
	assert_bool(is_instance_valid(_viewer)).is_false()
