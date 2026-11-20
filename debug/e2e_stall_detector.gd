## e2e ドライバーの「画面が進まない」検出（デバッグ専用。debug/ なので製品の複製には入らない）。
##
## 目的: 画面が遷移しないまま同じ場所を押し続け、長く待った末に原因の分からない TIMEOUT になるのを防ぐ。
##       「同じ画面に stall_sec 秒以上いて、その間に stall_clicks 回以上クリックした」を進まない状態とみなし、
##       すぐ FAIL にして、直近の API エラー（メソッド・パス・HTTP 状態・Kind）を添える。
## 誤検出を避ける考え方:
##   - 秒数と回数の両方を満たしたときだけ失敗にする。--e2e-dwell で長く止まっているだけ（クリックが少ない）や、
##     エラー表示の再試行を数回押す確認（--e2e-fail-login=503 など。既定の 5 回に届かない）は失敗にしない。
##   - 画面（シーンのパス）が変わったら秒数も回数も 0 に戻す（遷移したら進んでいる）。
##   - 時間は呼び出し側が渡す delta の合計で数える（フレーム単位のテストができる）。
## 使い方（e2e_driver.gd）: 毎フレーム observe(scene, delta)、クリックの送信ごとに record_click()、
##   is_stalled() が真なら format_fail_line(...) を出して終了コード 1 で終わる。
extends RefCounted

## 既定の待ち時間（秒）。規約画面の通常の進行は数秒なので、その数倍
const DEFAULT_STALL_SEC := 30.0
## 既定のクリック回数。再試行を数回押す確認（503 を 1〜3 回など）に届かない値
const DEFAULT_STALL_CLICKS := 5

## 進まないとみなす秒数と回数
var stall_sec: float
var stall_clicks: int
## 今の画面に入ってからの秒数・クリック回数
var _scene_path: String = ""
var _seconds: float = 0.0
var _clicks: int = 0
## 今の画面に入った時点の ApiClient.error_serial。これより後の失敗だけを「この画面での API エラー」とする
## （前の画面の古いエラーを、今の画面の原因として出さないため）
var _error_baseline: int = 0


func _init(seconds: float = DEFAULT_STALL_SEC, clicks: int = DEFAULT_STALL_CLICKS) -> void:
	stall_sec = seconds
	stall_clicks = clicks


## 引数（--e2e-stall-sec=<秒> / --e2e-stall-clicks=<回>）から作る。無い・数値でない（値なしの true を含む）は既定値に戻る。
## 秒が 0 以下なら検出しない（無効。stall_sec = 0 は is_stalled が常に偽）。
static func from_args(args: Dictionary) -> RefCounted:
	var seconds := DEFAULT_STALL_SEC
	var clicks := DEFAULT_STALL_CLICKS
	var seconds_value: Variant = args.get("e2e-stall-sec", null)
	if seconds_value is String and seconds_value.is_valid_float():
		seconds = seconds_value.to_float()
	var clicks_value: Variant = args.get("e2e-stall-clicks", null)
	if clicks_value is String and clicks_value.is_valid_int():
		clicks = maxi(1, clicks_value.to_int())
	return load("res://debug/e2e_stall_detector.gd").new(seconds, clicks)


## 1 フレーム進める。画面が変わったら秒数・回数を 0 に戻す（進んだとみなす）。
## error_serial は ApiClient.error_serial の現在値。画面が変わった時点の値を基準として覚える。
func observe(scene_path: String, delta: float, error_serial: int = 0) -> void:
	if scene_path != _scene_path:
		_scene_path = scene_path
		_seconds = 0.0
		_clicks = 0
		_error_baseline = error_serial
	_seconds += delta


## 画面を進めるためのクリックを 1 回送ったときに呼ぶ（規約の閲覧の開閉など、進行ではない操作は呼ばない）。
func record_click() -> void:
	_clicks += 1


## 進まない状態か。無効（stall_sec <= 0）なら常に偽。秒数と回数の両方が閾値以上で真。
func is_stalled() -> bool:
	if stall_sec <= 0.0:
		return false
	return _seconds >= stall_sec and _clicks >= stall_clicks


## 今の画面での経過秒・クリック回数（出力とテスト用）。
func seconds() -> float:
	return _seconds


func clicks() -> int:
	return _clicks


## 今の画面に入ってから起きた最後の API 失敗。無ければ空の辞書（前の画面のエラーは含めない）。
func scene_error(last_error: Dictionary) -> Dictionary:
	if int(last_error.get("serial", 0)) > _error_baseline:
		return last_error
	return {}


## 進まない失敗の行を作る。last_error は ApiClient.last_error（この画面より前のものは none にする）。
## retry_visible・status_text は画面のエラー表示（再試行ボタンが見えているときだけ文を添える）。
func fail_line(last_error: Dictionary, retry_visible: bool, status_text: String) -> String:
	return format_fail_line(
		_scene_path, scene_error(last_error), status_text if retry_visible else ""
	)


## ApiClient.last_error を `GET /agreement/pending status=405 kind=SERVER_ERROR` の形に整える。
## 空（API エラーなし）は "none"。
## 出力の形（FAIL 行の last_api_error= の後ろ）: `<メソッド> <パス> status=<HTTP 状態> kind=<AppError.Kind 名>`。
## 失敗行を 1 行で機械的に読めるよう、空白を含む項目は無い（パスはクエリ込みだが空白は入らない）。
static func format_last_api_error(error: Dictionary) -> String:
	if error.is_empty():
		return "none"
	var kind_index := int(error.get("kind", AppError.Kind.NONE))
	var kind_names := AppError.Kind.keys()
	var kind_name := "UNKNOWN"
	if kind_index >= 0 and kind_index < kind_names.size():
		kind_name = str(kind_names[kind_index])
	return (
		"%s %s status=%d kind=%s"
		% [
			str(error.get("method", "?")),
			str(error.get("endpoint", "?")),
			int(error.get("http_status", 0)),
			kind_name,
		]
	)


## E2E_RESULT: FAIL の行。screen_text は画面のエラー文（空なら付けない。改行は " / " にして 1 行を保つ）。
## 形: `E2E_RESULT: FAIL stalled scene=<シーン> last_api_error=<上> [screen_error="<文>"]`
static func format_fail_line(scene_path: String, error: Dictionary, screen_text: String) -> String:
	var line := (
		"E2E_RESULT: FAIL stalled scene=%s last_api_error=%s"
		% [scene_path, format_last_api_error(error)]
	)
	var text := screen_text.strip_edges().replace("\n", " / ")
	if text != "":
		line += ' screen_error="%s"' % text
	return line
