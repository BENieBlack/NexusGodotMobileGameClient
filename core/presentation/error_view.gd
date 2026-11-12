## エラーを画面に出す共通部品（メッセージのラベルと「再試行」ボタンの制御）。
##
## 目的: タイトルと規約画面が同じ手順（文言を出す → 再試行ボタンを出す → 429 の間は無効にする）で
##       エラーを見せるための、presenter 共通の部品。文言は ErrorMessages に置く。
## 使い方: ErrorView.show_error(status_label, retry_button, error)  失敗を表示する
##         ErrorView.hide_retry(retry_button)                       進行中に戻すとき（ボタンを隠す）
## 注意: 再試行は押した結果をそのまま再表示するだけで、自動では繰り返さない（client_design.md 1-3）。
class_name ErrorView
extends RefCounted

## ボタンに付ける、無効化の予約番号のメタ名（最新の予約だけが解除できる）
const LOCK_TOKEN_META := "retry_lock_token"


## 文言を出し、再試行ボタンを見せる。429 では retry_after の秒数だけボタンを無効にする。
static func show_error(status_label: Label, retry_button: Button, error: AppError) -> void:
	status_label.text = ErrorMessages.text(error)
	retry_button.visible = true
	var lock := ErrorMessages.retry_lock_seconds(error)
	if lock <= 0:
		retry_button.disabled = false
		return
	retry_button.disabled = true
	# 解除の予約に番号を付ける。先のエラー表示の予約が、後のエラー表示の無効化を途中で解かないため
	var token := Time.get_ticks_usec()
	retry_button.set_meta(LOCK_TOKEN_META, token)
	await _unlock_after(retry_button, lock, token)


## 再試行ボタンを隠して押せる状態に戻す（次のエラー表示のため）。進行中はボタンを見せない。
static func hide_retry(retry_button: Button) -> void:
	retry_button.visible = false
	retry_button.disabled = false


## 秒数が過ぎたらボタンを有効に戻す。待っている間に画面が破棄・遷移したら何もしない。
## 隠れている（進行中に戻った）とき、または後の予約に置き換わったときも触らない。
static func _unlock_after(retry_button: Button, seconds: int, token: int) -> void:
	if not retry_button.is_inside_tree():
		return
	await retry_button.get_tree().create_timer(float(seconds)).timeout
	if not is_instance_valid(retry_button) or not retry_button.visible:
		return
	if retry_button.get_meta(LOCK_TOKEN_META, 0) == token:
		retry_button.disabled = false
