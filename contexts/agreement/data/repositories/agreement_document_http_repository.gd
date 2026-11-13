## 規約本文（HTML）の取得（AgreementDocumentRepository の実装）。
##
## 目的: 規約の URL を解決し、認証なしの GET で本文を取り、UTF-8 の文字列にして返す。
## 流れ:
##   1. URL を解決する（resolve_url）。不正なら通信せず LOCAL の失敗
##   2. ApiClient.download で取得する（認証・X-Master ヘッダー無し。timeout は DEFAULT_TIMEOUT）。
##      通信断・タイムアウトは NETWORK、HTTP 200 以外は SERVER_ERROR（ApiClient が分類する）
##   3. 本文を UTF-8 の文字列にする。空（空白だけを含む）は PARSE の失敗
## 命名: 通信先が JSON API ではなく静的ファイルなので *_api_repository ではなく *_http_repository とした。
class_name AgreementDocumentHttpRepository
extends AgreementDocumentRepository

const INVALID_URL_MESSAGE := "規約の URL が正しくありません"

var _api_client: ApiClient


func _init(api_client: ApiClient) -> void:
	_api_client = api_client


func fetch_document(url: String) -> FetchAgreementDocumentResult:
	# --- 1. URL の解決 ---
	var resolved := resolve_url(url, ApiConfig.api_origin())
	if resolved == "":
		return FetchAgreementDocumentResult.new(
			"", AppError.new(AppError.Kind.LOCAL, INVALID_URL_MESSAGE)
		)

	# --- 2. 取得 ---
	var api_result := await _api_client.download(resolved, ApiClient.DEFAULT_TIMEOUT)
	if not api_result.ok:
		return FetchAgreementDocumentResult.new("", api_result.to_app_error())

	# --- 3. UTF-8 の文字列にする ---
	# 本文が空のとき、空の規約を「表示できた」ことにしない（サーバーの設定ミスに気づけるよう失敗にする）
	var html := api_result.raw_body.get_string_from_utf8()
	if html.strip_edges() == "":
		return FetchAgreementDocumentResult.new("", AppError.new(AppError.Kind.PARSE))
	return FetchAgreementDocumentResult.new(html)


## 規約の URL を、取得できる絶対 URL にする。
## 絶対 URL（http:// https://）はそのまま、"/" 始まりの相対パス（"//" 始まりは別ホストになるので除く）は
## origin（例: http://localhost:8090）に付ける。それ以外（空・不正）は空文字（呼び出し側が失敗にする）。
static func resolve_url(url: String, origin: String) -> String:
	var trimmed := url.strip_edges()
	if trimmed.begins_with("http://") or trimmed.begins_with("https://"):
		return trimmed
	if trimmed.begins_with("/") and not trimmed.begins_with("//"):
		return origin.rstrip("/") + trimmed
	return ""
