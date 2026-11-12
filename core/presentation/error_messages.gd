## エラー種別ごとの表示文言（client_design.md 1-3 の表）。画面（presenter）が共通で使う。
##
## 目的: どの画面でも同じ失敗が同じ文言で出るように、AppError → 文字列の対応を 1 か所に置く。
##       純粋な関数だけで Node に依存しないので、単体テストで文言を確かめられる。
## 使い方:
##   ErrorMessages.text(error)               表示する文言（メンテナンスはサーバーの title / message / end_at）
##   ErrorMessages.retry_lock_seconds(error) 再試行ボタンを無効にしておく秒数（429 の retry_after。無ければ 0）
## 注意: 文言は設計の既定案（Q3）。BUSINESS の message は本番でマスクされるので補助表示にとどめる。
class_name ErrorMessages
extends RefCounted

## 署名の時刻ずれ（sign_up の 401。本文の error）。端末の時刻を直せば直るので別の文言にする
const SIGNATURE_REQUEST_EXPIRED := "REQUEST_EXPIRED"


## 失敗の種別から、利用者に見せる文言を返す。
static func text(error: AppError) -> String:
	if error == null:
		return "エラーが発生しました"
	match error.kind:
		AppError.Kind.NETWORK:
			return "通信できませんでした。電波の良い場所でお試しください"
		AppError.Kind.MAINTENANCE:
			return _maintenance_text(error.maintenance)
		AppError.Kind.SERVER_BUSY:
			return "しばらくしてからお試しください"
		AppError.Kind.RATE_LIMITED:
			return _rate_limited_text(error.retry_after)
		AppError.Kind.CONFLICT:
			return "処理中です。しばらくしてからお試しください"
		AppError.Kind.BUSINESS:
			return _business_text(error)
		AppError.Kind.SESSION_EXPIRED:
			return "ログイン情報が無効になりました。最初からやり直します"
		AppError.Kind.VALIDATION:
			return "エラーが発生しました (422)"
		AppError.Kind.PARSE:
			return "サーバーの応答を読めませんでした"
		AppError.Kind.SIGNATURE:
			if error.error_name == SIGNATURE_REQUEST_EXPIRED:
				return "端末の時刻を確認してください"
			return "端末の確認に失敗しました"
		AppError.Kind.LOCAL:
			return error.message if error.message != "" else "エラーが発生しました"
		_:
			return _server_error_text(error)


## 再試行ボタンを無効にしておく秒数。429 の retry_after だけが対象で、他は即座に押せる（0）。
## 自動で再送しない（レート制限を悪化させない）ので、押せる時刻を知らせるだけ。
static func retry_lock_seconds(error: AppError) -> int:
	if error != null and error.kind == AppError.Kind.RATE_LIMITED:
		return maxi(error.retry_after, 0)
	return 0


static func _maintenance_text(maintenance: Dictionary) -> String:
	var title := str(maintenance.get("title", ""))
	var message := str(maintenance.get("message", ""))
	var end_at: Variant = maintenance.get("end_at", null)
	var lines: Array[String] = []
	if title != "":
		lines.append(title)
	if message != "":
		lines.append(message)
	# end_at は null のことがある（終了未定）。あるときだけ終了予定を足す
	if end_at != null and str(end_at) != "":
		lines.append("終了予定: " + str(end_at))
	if lines.is_empty():
		return "ただいまメンテナンス中です"
	return "\n".join(lines)


static func _rate_limited_text(retry_after: int) -> String:
	var text := "アクセスが集中しています。しばらくしてからお試しください"
	# 秒数は表示時点の値の固定文（カウントダウンしない。設計 1-3 の仮置き）
	if retry_after > 0:
		text = "アクセスが集中しています。あと約 %d 秒後にお試しください" % retry_after
	return text


static func _business_text(error: AppError) -> String:
	var text := "エラーが発生しました (コード: %d)" % error.error_code
	if error.message != "":
		text += "\n" + error.message
	return text


static func _server_error_text(error: AppError) -> String:
	if error.error_code >= 0:
		return "サーバーでエラーが発生しました (コード: %d)" % error.error_code
	return "サーバーでエラーが発生しました"
