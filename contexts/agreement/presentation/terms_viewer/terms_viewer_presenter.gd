## 規約の閲覧画面の presenter（client_design.md 1-2「規約の閲覧」）。
##
## 目的: 規約画面の「確認する」で開き、規約の HTML を取得して RichTextLabel に描く。外部ブラウザへ
##       出さずに読めるようにする（WebView は使わない）。規約画面の上に重ねる全画面のオーバーレイで、
##       「閉じる」で閉じると下の規約画面に戻る（遷移はしない）。
## 流れ:
##   1. 読み込み: 「読み込み中...」を出し、本文を取得する（fetch_agreement_document_use_case）
##      - 成功 → HtmlToBbcode で BBCode にして本文に出す（スクロールできる）
##      - 失敗 → エラー文と「再試行」「ブラウザで開く」（元の URL を OS.shell_open で外部ブラウザへ）
##   2. 再試行は取得からやり直す（押した結果をそのまま見せる。自動では繰り返さない）
##   3. 本文のリンクは http / https だけ OS.shell_open で開く（それ以外は無視。規約の HTML が書く href を信用しない）
## 二重取得の防止: 取得中は _is_loading を立て、再試行が連打されても 2 本目は取得しない。
## 画面の破棄: await から戻ったとき、閉じられて（ツリーの外に出て）いたら何もせず終わる。
## 依存: UseCase だけを呼ぶ。外部ブラウザを開く処理は Callable で受ける（テストは記録する偽物を渡す）。
class_name TermsViewerPresenter
extends Control

## 「閉じる」が押されたとき（規約画面が、開いている閲覧画面の参照を捨てるために受ける）
signal closed

const OPENABLE_SCHEMES: Array[String] = ["http://", "https://"]
const CONTENT_UNREADABLE_MESSAGE := "規約の内容を表示できませんでした"

var _fetch_document: FetchAgreementDocumentUseCase
var _title: String = ""
var _url: String = ""
## (url: String) -> 外部ブラウザで開く。既定は OS.shell_open
var _shell_open: Callable = Callable()
var _is_configured: bool = false
var _is_loading: bool = false

@onready var _title_label: Label = $VBoxContainer/TitleLabel
@onready var _status_label: Label = $VBoxContainer/StatusLabel
@onready var _body_label: RichTextLabel = $VBoxContainer/BodyLabel
@onready var _retry_button: Button = $VBoxContainer/RetryButton
@onready var _browser_button: Button = $VBoxContainer/BrowserButton
@onready var _close_button: Button = $VBoxContainer/CloseButton


## 取得の UseCase と、開く規約（表示名・URL）を渡す。_ready より前（add_child の前）に呼ぶ。
## shell_open を渡さなければ OS.shell_open を使う。
func setup(
	fetch_document: FetchAgreementDocumentUseCase,
	title: String,
	url: String,
	shell_open: Callable = Callable()
) -> void:
	_fetch_document = fetch_document
	_title = title
	_url = url
	_shell_open = shell_open if shell_open.is_valid() else Callable(OS, "shell_open")
	_is_configured = true


func _ready() -> void:
	if not _is_configured:
		setup(AppContext.fetch_agreement_document_use_case(), "", "")
	_title_label.text = _title
	_retry_button.pressed.connect(_on_retry_pressed)
	_browser_button.pressed.connect(_on_browser_pressed)
	_close_button.pressed.connect(_on_close_pressed)
	_body_label.meta_clicked.connect(_on_meta_clicked)
	await _load()


## 本文を取得して、画面の状態（読み込み中・表示・エラー）を決める。取得中は 2 本目を始めない。
func _load() -> void:
	if _is_loading:
		return
	_is_loading = true
	ErrorView.hide_retry(_retry_button)
	_browser_button.visible = false
	_body_label.text = ""
	_status_label.text = "読み込み中..."

	var result := await _fetch_document.handle(_url)
	_is_loading = false
	if not is_inside_tree():
		return

	var bbcode := HtmlToBbcode.to_bbcode(result.html) if result.ok else ""
	if result.ok and bbcode == "":
		# 取得はできたが、許可したタグの外だけで何も表示できない。空の画面を「成功」にしない
		result = FetchAgreementDocumentResult.new(
			"", AppError.new(AppError.Kind.LOCAL, CONTENT_UNREADABLE_MESSAGE)
		)
	if not result.ok:
		# 再試行と、外部ブラウザで読む逃げ道の両方を出す
		_browser_button.visible = true
		await ErrorView.show_error(_status_label, _retry_button, result.error)
		return
	_status_label.text = ""
	_body_label.text = bbcode


func _on_retry_pressed() -> void:
	await _load()


func _on_browser_pressed() -> void:
	_shell_open.call(_url)


func _on_close_pressed() -> void:
	closed.emit()
	queue_free()


## 本文のリンク。http / https 以外（javascript: や file: など）は開かない。
func _on_meta_clicked(meta: Variant) -> void:
	var target := str(meta)
	var lower := target.to_lower()
	for scheme in OPENABLE_SCHEMES:
		if lower.begins_with(scheme):
			_shell_open.call(target)
			return
