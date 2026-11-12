## 通信 1 回分の結果の値（client_design.md 2-1・3-5）。
##
## 目的: ApiClient.request() の戻り値。HTTP の細部（ステータス・error_code・ヘッダー）を
##       ここに閉じ込め、API Repository が to_app_error() で AppError に直して上位へ渡す。
##       UseCase・presenter は ApiResult を知らない。core/data の内部の型。
## 項目:
##   ok           成功（2xx で本文が読めた）なら true
##   kind         失敗の種別（成功なら AppError.Kind.NONE）
##   http_status  HTTP ステータス（通信自体が失敗したら 0）
##   error_code   業務エラーなどのコード（無ければ -1）
##   message      サーバーの message
##   data         本文の JSON（Dictionary。読めなければ空）
##   headers      応答ヘッダー（"Name: value" の配列）
##   raw_body     本文の生バイト（マスターのダウンロード用。JSON 呼び出しでは空）
##   retry_after  429 の待ち秒数（無ければ 0）
##   maintenance  503 メンテナンスの {title, message, start_at, end_at}
##   error_name   401（認証なし）の本文 error（INVALID_SIGNATURE など）
class_name ApiResult
extends RefCounted

var ok: bool = false
var kind: AppError.Kind = AppError.Kind.NONE
var http_status: int = 0
var error_code: int = -1
var message: String = ""
var data: Dictionary = {}
var headers: PackedStringArray = PackedStringArray()
var raw_body: PackedByteArray = PackedByteArray()
var retry_after: int = 0
var maintenance: Dictionary = {}
var error_name: String = ""


## 成功の結果を作る。
static func make_ok(
	p_status: int, p_data: Dictionary, p_headers: PackedStringArray = PackedStringArray()
) -> ApiResult:
	var result := ApiResult.new()
	result.ok = true
	result.kind = AppError.Kind.NONE
	result.http_status = p_status
	result.data = p_data
	result.headers = p_headers
	return result


## 失敗の結果を作る。付帯情報（error_code など）は呼び出し側が後から入れる。
static func make_error(
	p_kind: AppError.Kind, p_status: int = 0, p_message: String = ""
) -> ApiResult:
	var result := ApiResult.new()
	result.ok = false
	result.kind = p_kind
	result.http_status = p_status
	result.message = p_message
	return result


## 失敗を AppError に直す。成功の結果に対して呼ぶのは誤り（その場合は SERVER_ERROR を返して警告する）。
func to_app_error() -> AppError:
	if ok:
		push_warning("ApiResult.to_app_error: 成功の結果に対して呼ばれました")
		return AppError.new(AppError.Kind.SERVER_ERROR, "成功の結果です")
	var error := AppError.new(kind, message)
	error.error_code = error_code
	error.retry_after = retry_after
	error.maintenance = maintenance
	error.error_name = error_name
	return error
