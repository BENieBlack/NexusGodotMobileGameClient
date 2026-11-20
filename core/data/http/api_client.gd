## HTTP の窓口（client_design.md 3-5、architecture.md 3 節 core/data/http）。
##
## 目的: サーバー API への通信を 1 か所に集め、次を閉じ込める。上位（API Repository）は
##       `await api_client.request(...)` で ApiResult を受け取るだけで、HTTP の細部を知らない。
##   - 1 呼び出しごとに HTTPRequest を作って破棄する（同時実行できる。timeout を必ず付ける）
##   - HTTP ステータスと error_code による失敗の分類（AppError.Kind）
##   - 401 のとき refresh を 1 本にまとめ、同じリクエストを 1 回だけ再送する
##   - X-Master-Hash の付与、X-Master-Update-Required の検出、冪等キーの付与
##
## 使い方:
##   1. AppContext が 1 つ生成して add_child し、configure() で 2 つの契約の実装を渡す
##   2. `var result: ApiResult = await api_client.request("GET", "/auth/version?deploy_version=0",
##      {}, {"auth": false})`
##      options: auth（既定 true。false なら Authorization を付けず、401 でも refresh しない）、
##               idempotency_key（付ける冪等キー）、extra_headers（PackedStringArray）、
##               allow_empty_body（既定 false。true なら 2xx の空本文・空配列 `[]` を空の辞書で成功扱い）、
##               timeout（秒。既定 DEFAULT_TIMEOUT）
##   3. 失敗は例外にせず ApiResult（ok = false）で返す。分類は api_result.gd のとおり
##
## 依存の向き（architecture.md 2-1）: core は contexts・master_data・app を参照しない。
##   - token と master_hash は、core/domain の契約（ApiAuthProvider / MasterHashProvider）から受け取る
##   - EventBus を直接呼ばず、自分のシグナル session_expired / master_update_required を出す。
##     AppContext が EventBus に中継する（core/data はオートロード名を参照できない。依存チェック A1）
##
## テスト: HTTP の送信は _send_http() の 1 か所に閉じてある。テストは継承してこれを差し替え、
##       実通信をしない（tests/unit/core/data/http/api_client_test.gd）。
class_name ApiClient
extends Node

## refresh に失敗し、セッションを破棄すべきとき（10002 / 10003 / HTTP 200 以外 / 解析失敗 など）。
## AppContext が EventBus.session_expired に中継し、auth / player / login が状態を空にする
signal session_expired

## 200 応答に X-Master-Update-Required が付いていたとき。待たずに結果を返し、
## 更新は受け手（master_data。AppContext が登録）が裏で行う
signal master_update_required

## refresh が終わったことを、待機中のリクエストに知らせる（内部用。結果は _last_refresh_failure）
signal refresh_finished

## サーバー独自の業務エラーの HTTP ステータス（api.md。2xx 扱いなので専用に見分ける）
const HTTP_BUSINESS_ERROR := 299

## 通信の timeout（秒）。既定は無制限で、通信が詰まると「認証中...」のまま戻らなくなる
## （client_design.md 0 節 n）ため必ず付ける。15 秒は設計の既定値（8 節 10）
const DEFAULT_TIMEOUT := 15.0

## マスターの配信ファイル（大きい）の timeout（秒）。設計 8 節 10 の仮置き
const DOWNLOAD_TIMEOUT := 60.0

## 503 のうち、メンテナンスではなくロック基盤の不達を表す error_code（サーバー api.md）
const ERROR_CODE_SERVER_BUSY := 50300

## version API のパスの先頭。この応答に付いた X-Master-Update-Required は無視する（本文の needs_update で足りる）
const VERSION_PATH_PREFIX := "/auth/version"

const REFRESH_PATH := "/auth/refresh_token"

## X-Platform の欠落・不正を表す error_code（サーバー api.md 10 節。HTTP 299。仮置きのコード）。
## 分類（BUSINESS）はこの値に依存させず、開発者向けの push_error を出す判定にだけ使う
const ERROR_CODE_PLATFORM_REJECTED := 99003
## 言語ヘッダーの名前（サーバーの ResolveLanguage が解釈する標準ヘッダー。名前を変えるときはここだけ）
const LANGUAGE_HEADER := "Accept-Language"

## refresh の失敗のうち「refresh を試せなかっただけ」の種別。セッションは破棄せず、この失敗を
## そのまま呼び出し元へ返す（電波が切れただけでログアウトさせない。client_design.md 3-5）
const NOT_TRIED_KINDS: Array[AppError.Kind] = [
	AppError.Kind.NETWORK,
	AppError.Kind.RATE_LIMITED,
	AppError.Kind.MAINTENANCE,
	AppError.Kind.SERVER_BUSY,
]

## デバッグ専用: 応答の差し替え。(method: String, endpoint: String) -> ApiResult か null を返す Callable を
## 入れると、_send の前に呼ばれ、ApiResult が返れば通信せずにそれを結果にする（null なら本物を送る）。
## e2e ドライバー（debug/e2e_driver.gd の --e2e-fail-login）が login の失敗を再現するためだけに使う。
## 製品のコードは設定しない（未設定なら何も起きない）。
var debug_override: Callable = Callable()

## 直近に失敗した API 呼び出しの記録（デバッグ・e2e の原因表示用）。空なら失敗なし。
## キー: serial（int。失敗のたびに 1 ずつ増える連番。「ある時点より後のエラーか」を見分ける）/
##       method（String）/ endpoint（String。クエリは落としたパス）/ http_status（int。通信失敗は 0）/
##       kind（AppError.Kind）。保持するだけで何もしない軽い仕組み（本文・ヘッダー・トークンは入れない）。
## request() と debug_override の偽の失敗は記録する。download() は _send を通らないので記録しない。
## e2e ドライバー（debug/e2e_driver.gd）が、画面が進まないときに「どの API がなぜ失敗したか」を
## 失敗メッセージに添えるために読む。製品のコードは読まない。
var last_error: Dictionary = {}
## 記録した失敗の回数（last_error の serial の元）。成功では増えない
var error_serial: int = 0

## 今 refresh を実行中か（refresh を 1 本にまとめるためのフラグ）
var _is_refreshing: bool = false

## 直近の refresh の失敗。成功なら null。並行して待っていた呼び出しは同じ ApiResult を共有する
## （破棄を伴う失敗の session_expired の emit は refresh 1 回につき 1 回だけなので無害）
var _last_refresh_failure: ApiResult = null

var _auth_provider: ApiAuthProvider = null
var _master_hash_provider: MasterHashProvider = null
## 全リクエストに付ける X-Platform の値。空文字なら付けない（e2e が欠落を再現するため。set_platform("")）
var _platform: String = ""


## token と master_hash の供給元を渡す。AppContext が組み立て時に 1 回呼ぶ。
## 未設定（null）でも動く（トークンなし・ハッシュなしとして扱う）。
## platform は X-Platform の値。1 起動の間で変わらないので組み立て時に 1 回だけ受け取る
## （既定は ApiConfig.platform()。テストは値を差し替えられる）。
func configure(
	auth_provider: ApiAuthProvider,
	master_hash_provider: MasterHashProvider,
	platform: String = ApiConfig.platform()
) -> void:
	_auth_provider = auth_provider
	_master_hash_provider = master_hash_provider
	_platform = platform


## X-Platform の値を差し替える。空文字にするとヘッダーを付けなくなる（デバッグ専用:
## e2e の --e2e-omit-platform がサーバーの 99003 を再現するために使う。製品は呼ばない）。
func set_platform(platform: String) -> void:
	_platform = platform


## API を 1 回呼ぶ（401 なら refresh して 1 回だけ再送する）。
## 引数: method は "GET" か "POST"、endpoint は "/auth/login" のような API のパス（ベース URL は
##       ApiConfig）、body は POST の JSON、options は上の使い方のとおり。
## 戻り値: ApiResult。失敗でも例外にしない（ok = false と kind で返す）。
func request(
	method: String, endpoint: String, body: Dictionary = {}, options: Dictionary = {}
) -> ApiResult:
	var use_auth: bool = options.get("auth", true)
	# 送った時点のトークンを覚えておく。401 を受けたとき「自分が古いトークンで送っただけで、
	# 既に誰かが refresh 済み」かを見分けるため（refresh 済みなら再 refresh せず再送だけする）
	var used_token := _current_access_token() if use_auth else ""

	# --- 1. 1 回目の送信 ---
	var result := await _send(method, endpoint, body, options)
	if not (use_auth and result.http_status == 401):
		return result

	# --- 2. 401: refresh を 1 本にまとめる ---
	# 認証付きで 401 を受けたときだけ refresh する。refresh の 429（15 分 10 回）を避けるため、
	# 同時に複数の 401 が来ても実際に送る refresh は 1 本にする
	var failure: ApiResult = null
	if _is_refreshing:
		# 進行中の refresh の完了を待ち、その結果（成功なら null）に従う
		await refresh_finished
		failure = _last_refresh_failure
	elif _current_access_token() != used_token:
		# 自分が送ったあとに refresh が済んでいた。同じトークンで refresh すると 10003 になるので再送だけ行う
		failure = null
	else:
		failure = await _refresh()
	if failure != null:
		return failure

	# --- 3. 同じリクエストを 1 回だけ再送する ---
	# 冪等キーは options に入っているので同じ値で送られる（401 は冪等より手前で返り、保存されない。3-4）
	result = await _send(method, endpoint, body, options)
	if result.http_status == 401:
		# 再送も 401 なら、refresh を繰り返さずに打ち切る（旧実装のループを止める）。
		# 認証が成立しないままなので、セッションも破棄する
		return _expire_session()
	return result


## マスターの配信ファイルをダウンロードする（認証なし・X-Master-* なし・JSON ではない）。
## 引数: url は絶対 URL（相対パスの解決は呼び出し側 = master_data の API Repository）。
## 戻り値: 成功なら ApiResult.ok = true で raw_body にバイト列。HTTP 200 以外は SERVER_ERROR、
##         通信失敗は NETWORK。
func download(url: String, timeout: float = DOWNLOAD_TIMEOUT) -> ApiResult:
	var headers := PackedStringArray(["Accept: application/octet-stream"])
	var response := await _send_http("GET", url, headers, "", timeout)
	var result_code: int = response.get("result", HTTPRequest.RESULT_CANT_CONNECT)
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return ApiResult.make_error(AppError.Kind.NETWORK)
	var status: int = response.get("status", 0)
	if status != 200:
		return ApiResult.make_error(AppError.Kind.SERVER_ERROR, status)
	var result := ApiResult.make_ok(200, {}, response.get("headers", PackedStringArray()))
	result.raw_body = response.get("body", PackedByteArray())
	return result


## レスポンスヘッダーから X-Master-Update-Required を判定する。
## ヘッダー名は大文字小文字を区別せず、値は "true" か "1" を真とする（旧 master_hash_test の期待）。
static func has_master_update_required(headers: PackedStringArray) -> bool:
	for header in headers:
		var separator_index := header.find(":")
		if separator_index < 0:
			continue
		var header_name := header.substr(0, separator_index).strip_edges().to_lower()
		var value := header.substr(separator_index + 1).strip_edges().to_lower()
		if header_name == "x-master-update-required":
			return value == "true" or value == "1"
	return false


## ヘッダー配列から名前に一致する値を返す（無ければ空文字）。名前は大文字小文字を区別しない
## （has_master_update_required と同じ走査）。サーバー時刻の Date の取り出しに使う。
static func find_header(headers: PackedStringArray, header_name: String) -> String:
	var wanted := header_name.to_lower()
	for header in headers:
		var separator_index := header.find(":")
		if separator_index < 0:
			continue
		if header.substr(0, separator_index).strip_edges().to_lower() == wanted:
			return header.substr(separator_index + 1).strip_edges()
	return ""


## HTTP を実際に送る唯一の場所。テストはここを差し替える（継承して上書き）。
## 戻り値の辞書: {"result": HTTPRequest.Result, "status": HTTP ステータス,
##   "headers": PackedStringArray, "body": PackedByteArray}。
## 送れなかった（リクエスト作成の失敗）ときも result に失敗を入れて返す。
## 1 呼び出しごとに HTTPRequest を作って破棄するので、同時に何本でも送れる。
func _send_http(
	method: String, url: String, headers: PackedStringArray, body: String, timeout: float
) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	var http_method := HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET
	var error := http.request(url, headers, http_method, body)
	if error != OK:
		http.queue_free()
		return {
			"result": HTTPRequest.RESULT_CANT_CONNECT,
			"status": 0,
			"headers": PackedStringArray(),
			"body": PackedByteArray(),
		}
	var response: Array = await http.request_completed
	http.queue_free()
	return {
		"result": response[0],
		"status": response[1],
		"headers": response[2],
		"body": response[3],
	}


## 1 回分の送信と分類。ヘッダーの組み立て → 送信 → 分類 → X-Master-Update-Required の検出。
func _send(method: String, endpoint: String, body: Dictionary, options: Dictionary) -> ApiResult:
	# デバッグの差し替えがあれば、通信せずにその結果を返す（上の debug_override の注記）
	if debug_override.is_valid():
		var faked: Variant = debug_override.call(method, endpoint)
		if faked is ApiResult:
			_remember_error(method, endpoint, faked)
			return faked
	var use_auth: bool = options.get("auth", true)
	var headers := _build_headers(
		use_auth, str(options.get("idempotency_key", "")), options.get("extra_headers", [])
	)
	# GET は本文を送らない（JSON.stringify({}) = "{}" を GET に載せないため）
	var body_string := JSON.stringify(body) if method == "POST" else ""
	var timeout := float(options.get("timeout", DEFAULT_TIMEOUT))

	var response := await _send_http(
		method, ApiConfig.api_base_url() + endpoint, headers, body_string, timeout
	)
	var result := _classify(response, use_auth, bool(options.get("allow_empty_body", false)))
	_remember_error(method, endpoint, result)

	# X-Platform の欠落・不正（299 の 99003）は利用者には直せない実装の誤り。画面は汎用の
	# BUSINESS 表示のままにし、開発者が気づけるようログに 1 回だけ出す（値は Apple / Google のみで秘密ではない）
	if result.kind == AppError.Kind.BUSINESS and result.error_code == ERROR_CODE_PLATFORM_REJECTED:
		push_error("X-Platform がサーバーに拒否されました（設定: %s）" % _platform)

	# マスターの更新要求は、サーバーが HTTP 200 の応答にだけ付ける（299・4xx・5xx には付かない）。
	# version 自体の応答は本文の needs_update で判定できるので無視する。待たずに結果を返す
	if result.ok and result.http_status == 200 and not endpoint.begins_with(VERSION_PATH_PREFIX):
		if has_master_update_required(result.headers):
			master_update_required.emit()
	return result


## 失敗した結果なら last_error に上書きで残す（成功では何もしない。直近の失敗を消さない）。
func _remember_error(method: String, endpoint: String, result: ApiResult) -> void:
	if result.ok:
		return
	error_serial += 1
	last_error = {
		"serial": error_serial,
		"method": method,
		# クエリ（?deploy_version=0 など）は落とす（値に秘密が混ざらないように、パスだけ残す）
		"endpoint": endpoint.split("?")[0],
		"http_status": result.http_status,
		"kind": result.kind,
	}


## リクエストヘッダーを組み立てる。
## Authorization は認証付きでトークンが在るときだけ。X-Master-Hash は全リクエストに（空なら付けない）。
## Accept-Language（ApiConfig.language()）も X-Platform と同じ 1 か所で全リクエストに付ける（download() には付かない）。
## X-Platform は request() を通る全リクエスト（refresh・GET /auth/version を含む）にここ 1 か所で付ける
## （空なら付けない）。署名の対象ではない。download()（配信ホスト・規約本文）は _send を通らないので付かない。
## ログにトークンや本文を出さない（client_design.md 8 節 11）。
func _build_headers(
	use_auth: bool, idempotency_key: String, extra_headers: Variant
) -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if use_auth:
		var token := _current_access_token()
		if token != "":
			headers.append("Authorization: Bearer " + token)
	if _master_hash_provider != null:
		var master_hash := _master_hash_provider.master_hash()
		if master_hash != "":
			headers.append("X-Master-Hash: " + master_hash)
	if _platform != "":
		headers.append("X-Platform: " + _platform)
	# 言語は固定（ja）。X-Platform と同じ位置で全 request() に付ける。付けない状態は作らない
	headers.append(LANGUAGE_HEADER + ": " + ApiConfig.language())
	if idempotency_key != "":
		headers.append("X-Unique-Request-Identifier: " + idempotency_key)
	for header in extra_headers:
		headers.append(str(header))
	return headers


## HTTP の結果を ApiResult に分類する（client_design.md 3-5 の判定の順）。
## 1. 通信自体の失敗 → NETWORK  2. 401  3. 429  4. 503  5. 409  6. 299  7. 422・その他の非 2xx
## 8. 2xx で本文が JSON(Dictionary) でない → PARSE。401・429・503（メンテ）は error_code を持たない。
func _classify(response: Dictionary, use_auth: bool, allow_empty_body: bool = false) -> ApiResult:
	var result_code: int = response.get("result", HTTPRequest.RESULT_CANT_CONNECT)
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return ApiResult.make_error(AppError.Kind.NETWORK)

	var status: int = response.get("status", 0)
	var headers: PackedStringArray = response.get("headers", PackedStringArray())
	var body: PackedByteArray = response.get("body", PackedByteArray())

	# 本文は 1 度だけ読む。読めない・Dictionary でないときは parsed = false（失敗系では空の辞書で続ける）
	var json := JSON.new()
	var text := body.get_string_from_utf8()
	var parsed := json.parse(text) == OK and json.data is Dictionary
	# サーバーは「返す項目が無い」成功（consent など）を `[]` で返す（PHP の空配列は JSON の配列になるため）。
	# 空の配列・空の本文は、呼び出し側が options の allow_empty_body で許したとき、HTTP 2xx（299 を除く）に
	# 限り「空の辞書」として成功扱いにする。既定では許さない: プロキシなどが返した空の 200 を login が
	# 成功と誤認し、player とログインボーナスを空で置き換えてしまうのを防ぐため（consent だけが指定する）。
	# 要素のある配列は許可の有無にかかわらず PARSE。299（業務エラー）は error_code を読むので辞書が必須
	if (
		allow_empty_body
		and not parsed
		and status >= 200
		and status < 300
		and status != HTTP_BUSINESS_ERROR
	):
		if text.strip_edges() == "" or (json.parse(text) == OK and json.data == []):
			parsed = true
	# 空の配列・空本文で成功扱いにした場合も、data は空の辞書になる
	var data: Dictionary = json.data if json.data is Dictionary and parsed else {}
	var server_message := str(data.get("message", ""))

	var result: ApiResult
	if status == 401:
		# 認証付き: トークン期限切れ（refresh の対象）。認証なし: sign_up の署名不正（本文の error で文言を分ける）
		if use_auth:
			result = ApiResult.make_error(AppError.Kind.SESSION_EXPIRED, status, server_message)
		else:
			result = ApiResult.make_error(AppError.Kind.SIGNATURE, status, server_message)
			result.error_name = str(data.get("error", ""))
	elif status == 429:
		result = ApiResult.make_error(AppError.Kind.RATE_LIMITED, status, server_message)
		result.retry_after = int(data.get("retry_after", 0))
	elif status == 503:
		result = _classify_service_unavailable(data, server_message)
	elif status == 409:
		result = ApiResult.make_error(AppError.Kind.CONFLICT, status, server_message)
	elif status == HTTP_BUSINESS_ERROR:
		if not parsed:
			return ApiResult.make_error(AppError.Kind.PARSE, status)
		result = ApiResult.make_error(AppError.Kind.BUSINESS, status, server_message)
		result.error_code = int(data.get("error_code", -1))
	elif status == 422:
		result = ApiResult.make_error(AppError.Kind.VALIDATION, status, server_message)
	elif status < 200 or status >= 300:
		result = ApiResult.make_error(AppError.Kind.SERVER_ERROR, status, server_message)
		if data.has("error_code"):
			result.error_code = int(data["error_code"])
	elif not parsed:
		return ApiResult.make_error(AppError.Kind.PARSE, status)
	else:
		return ApiResult.make_ok(status, data, headers)

	result.data = data
	result.headers = headers
	return result


## 503 を、ロック基盤の不達（error_code = 50300 → SERVER_BUSY）とメンテナンス（error_code 無し）に分ける。
func _classify_service_unavailable(data: Dictionary, server_message: String) -> ApiResult:
	if data.has("error_code") and int(data["error_code"]) == ERROR_CODE_SERVER_BUSY:
		var busy := ApiResult.make_error(AppError.Kind.SERVER_BUSY, 503, server_message)
		busy.error_code = ERROR_CODE_SERVER_BUSY
		return busy
	var maintenance := ApiResult.make_error(AppError.Kind.MAINTENANCE, 503, server_message)
	maintenance.maintenance = {
		"title": data.get("title", ""),
		"message": data.get("message", ""),
		"start_at": data.get("start_at", null),
		"end_at": data.get("end_at", null),
	}
	return maintenance


## refresh を 1 本として実行する。成功なら null、失敗なら呼び出し元へ返す ApiResult。
## 待機中のリクエストへは refresh_finished で知らせる（結果は _last_refresh_failure）。
func _refresh() -> ApiResult:
	_is_refreshing = true
	_last_refresh_failure = await _do_refresh()
	_is_refreshing = false
	refresh_finished.emit()
	return _last_refresh_failure


## refresh の本体。ログアウト扱い（セッション破棄）にする場合と、しない場合を分ける（D9）。
## セッション破棄: 保存の refresh_token が空 / 299 の 10002・10003 を含む「HTTP 200 以外」/ 本文の解析失敗 /
##   access_token が空。
## 破棄しない: 通信断・429・503（メンテ・基盤不達）。refresh を試せなかっただけで、セッションは生きている。
func _do_refresh() -> ApiResult:
	if _auth_provider == null or _auth_provider.refresh_token() == "":
		return _expire_session()

	# refresh 要求は Authorization を付けない（サーバーはアクセストークンを見ない）。auth = false で 401 の再 refresh も防ぐ
	var refresh_token := _auth_provider.refresh_token()
	var result := await _send(
		"POST", REFRESH_PATH, {"refresh_token": refresh_token}, {"auth": false}
	)
	if not result.ok:
		# 試せなかっただけの失敗は、そのまま返してセッションを保つ（下の NOT_TRIED_KINDS）
		if NOT_TRIED_KINDS.has(result.kind):
			return result
		return _expire_session()
	if result.http_status != 200:
		return _expire_session()

	var token := JsonReader.get_dict(result.data, "token")
	var new_access := str(token.get("access_token", ""))
	if new_access == "":
		return _expire_session()
	# refresh_token が応答に無いときは、手元の値を維持する（空で上書きして次の refresh を失わないため）
	var new_refresh := str(token.get("refresh_token", ""))
	if new_refresh == "":
		new_refresh = refresh_token
	_auth_provider.save_tokens(new_access, new_refresh)
	return null


## セッションを破棄する。シグナルで知らせ（AppContext が EventBus へ中継）、SESSION_EXPIRED を返す。
## トークンの消去は受け手（auth など）が行う。ApiClient はトークンを持たない。
func _expire_session() -> ApiResult:
	session_expired.emit()
	return ApiResult.make_error(AppError.Kind.SESSION_EXPIRED, 401)


func _current_access_token() -> String:
	if _auth_provider == null:
		return ""
	return _auth_provider.access_token()
