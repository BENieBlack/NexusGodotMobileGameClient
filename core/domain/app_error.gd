## 失敗の理由を表す値（architecture.md 3 節 core/domain、client_design.md 1-3 エラーの分類）。
##
## 目的: HTTP ステータスや error_code といった通信の細部を上位（UseCase・presenter）に見せず、
##       「何の種類の失敗か（kind）」と、表示に要る付帯情報だけを渡す。
## 使い方: ApiResult.to_app_error() が作る。presenter は kind で文言と動線（再試行・ボタン無効化）を決める。
## 付帯情報:
##   error_code     業務エラー（HTTP 299）などのコード。無ければ -1
##   message        サーバーの message（本番ではマスクされるので補助表示）
##   retry_after    RATE_LIMITED の待ち秒数。無ければ 0
##   maintenance    MAINTENANCE の {title, message, start_at, end_at}。それ以外は空
##   error_name     SIGNATURE の本文 error（INVALID_SIGNATURE / REQUEST_EXPIRED など）
class_name AppError
extends RefCounted

## 失敗の種別。判定の順序と条件は client_design.md 1-3 / 3-5 のとおり。
## NONE は「成功（失敗ではない）」を表す値で、ApiResult が成功のときにだけ使う。
## LOCAL は端末内の失敗（保存・DB を開けない等）。サーバー由来ではなく、設計の表に無い追加の種別
enum Kind {
	NONE,
	NETWORK,
	MAINTENANCE,
	SERVER_BUSY,
	RATE_LIMITED,
	CONFLICT,
	BUSINESS,
	SESSION_EXPIRED,
	VALIDATION,
	SERVER_ERROR,
	PARSE,
	SIGNATURE,
	LOCAL,
}

var kind: Kind = Kind.SERVER_ERROR
var error_code: int = -1
var message: String = ""
var retry_after: int = 0
var maintenance: Dictionary = {}
var error_name: String = ""


func _init(p_kind: Kind = Kind.SERVER_ERROR, p_message: String = "") -> void:
	kind = p_kind
	message = p_message
