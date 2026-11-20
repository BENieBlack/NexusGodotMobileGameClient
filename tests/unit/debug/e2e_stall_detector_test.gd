## e2e の「画面が進まない」検出のテスト（debug/e2e_stall_detector.gd）。
##
## 規約画面で API が 405 になり同意ボタンが押せないのに、ドライバーが押し続けて原因不明の TIMEOUT になった。
## 検出（秒数 + クリック回数）、遷移でのリセット、dwell 中の誤検出なし、失敗行の整形を確かめる。
extends GdUnitTestSuite

const DETECTOR := "res://debug/e2e_stall_detector.gd"
const AGREEMENT := "res://contexts/agreement/presentation/agreement.tscn"
const HOME := "res://contexts/home/presentation/home.tscn"


## 秒数 seconds ぶん（1 秒刻み）進め、interval 秒ごとにクリックを記録する。
func _run(detector: RefCounted, scene: String, seconds: int, click_every: int) -> void:
	for t in range(1, seconds + 1):
		detector.observe(scene, 1.0)
		if click_every > 0 and t % click_every == 0:
			detector.record_click()


## (a) 前提: 同じ画面で 30 秒・5 回以上押す。期待: 進まない（FAIL）。
func test_stalled_when_same_scene_and_many_clicks() -> void:
	var detector: RefCounted = load(DETECTOR).new(30.0, 5)
	_run(detector, AGREEMENT, 30, 3)
	assert_bool(detector.is_stalled()).is_true()


## (a) 前提: 秒数だけ・回数だけ満たす。期待: 失敗にしない（両方が要る）。
func test_not_stalled_unless_both_conditions() -> void:
	var seconds_only: RefCounted = load(DETECTOR).new(30.0, 5)
	_run(seconds_only, AGREEMENT, 60, 0)
	assert_bool(seconds_only.is_stalled()).is_false()
	var clicks_only: RefCounted = load(DETECTOR).new(30.0, 5)
	_run(clicks_only, AGREEMENT, 10, 1)
	assert_bool(clicks_only.is_stalled()).is_false()


## (b) 前提: 閾値の直前まで押したあと画面が遷移。期待: 秒数・回数が 0 に戻り、失敗にならない。
func test_reset_on_scene_change() -> void:
	var detector: RefCounted = load(DETECTOR).new(30.0, 5)
	_run(detector, AGREEMENT, 29, 5)
	detector.observe(HOME, 1.0)
	assert_int(detector.clicks()).is_equal(0)
	assert_float(detector.seconds()).is_equal_approx(1.0, 0.001)
	_run(detector, HOME, 20, 4)
	assert_bool(detector.is_stalled()).is_false()


## (c) 前提: dwell 10 秒で再試行を 3 回だけ押す（40 秒）。期待: 失敗にしない（回数が既定の 5 に届かない）。
func test_not_stalled_during_dwell_with_few_clicks() -> void:
	var detector: RefCounted = load(DETECTOR).new(30.0, 5)
	_run(detector, "res://app/title/title.tscn", 40, 12)
	assert_int(detector.clicks()).is_equal(3)
	assert_bool(detector.is_stalled()).is_false()


## 引数: 値を読み、不正・無しは既定、秒 0 は無効（常に偽）。
func test_from_args() -> void:
	var detector: RefCounted = load(DETECTOR).from_args(
		{"e2e-stall-sec": "10", "e2e-stall-clicks": "2"}
	)
	assert_float(detector.stall_sec).is_equal(10.0)
	assert_int(detector.stall_clicks).is_equal(2)
	var defaults: RefCounted = load(DETECTOR).from_args({"e2e-stall-sec": true})
	assert_float(defaults.stall_sec).is_equal(30.0)
	assert_int(defaults.stall_clicks).is_equal(5)
	var disabled: RefCounted = load(DETECTOR).from_args({"e2e-stall-sec": "0"})
	_run(disabled, AGREEMENT, 500, 1)
	assert_bool(disabled.is_stalled()).is_false()


## (d) 前提: 405 の記録。期待: `GET /agreement/pending status=405 kind=SERVER_ERROR`。
func test_format_last_api_error() -> void:
	var error := {
		"method": "GET",
		"endpoint": "/agreement/pending",
		"http_status": 405,
		"kind": AppError.Kind.SERVER_ERROR,
	}
	assert_str(load(DETECTOR).format_last_api_error(error)).is_equal(
		"GET /agreement/pending status=405 kind=SERVER_ERROR"
	)
	# 通信失敗は status=0。記録なしは none
	var network := {
		"method": "POST", "endpoint": "/auth/login", "http_status": 0, "kind": AppError.Kind.NETWORK
	}
	assert_str(load(DETECTOR).format_last_api_error(network)).is_equal(
		"POST /auth/login status=0 kind=NETWORK"
	)
	assert_str(load(DETECTOR).format_last_api_error({})).is_equal("none")


## (d) FAIL 行の形。画面のエラー文は改行を " / " にして 1 行で添え、空なら付けない。
func test_format_fail_line() -> void:
	var error := {
		"method": "GET", "endpoint": "/x", "http_status": 405, "kind": AppError.Kind.SERVER_ERROR
	}
	assert_str(load(DETECTOR).format_fail_line(AGREEMENT, error, "失敗\nもう一度")).is_equal(
		(
			(
				"E2E_RESULT: FAIL stalled scene=%s last_api_error=GET /x status=405"
				+ ' kind=SERVER_ERROR screen_error="失敗 / もう一度"'
			)
			% AGREEMENT
		)
	)
	assert_str(load(DETECTOR).format_fail_line(AGREEMENT, {}, "")).is_equal(
		"E2E_RESULT: FAIL stalled scene=%s last_api_error=none" % AGREEMENT
	)


## 前提: 前の画面で失敗（serial 1）→ 次の画面に遷移 → API エラーなしで止まる。期待: この画面のエラーは none。
func test_error_from_previous_scene_is_none() -> void:
	var detector: RefCounted = load(DETECTOR).new(30.0, 5)
	var old_error := {
		"serial": 1,
		"method": "POST",
		"endpoint": "/a",
		"http_status": 0,
		"kind": AppError.Kind.NETWORK
	}
	detector.observe(HOME, 1.0, 1)
	_run_with_serial(detector, AGREEMENT, 30, 1)
	assert_dict(detector.scene_error(old_error)).is_empty()
	assert_str(detector.fail_line(old_error, false, "")).contains("last_api_error=none")


## 前提: 画面に入った後で失敗（serial 1 → 2）。期待: その内容が出る。さらに 3 で上書きされたら 3。
func test_error_in_same_scene_is_reported() -> void:
	var detector: RefCounted = load(DETECTOR).new(30.0, 5)
	detector.observe(AGREEMENT, 1.0, 1)
	var second := {
		"serial": 2,
		"method": "GET",
		"endpoint": "/b",
		"http_status": 405,
		"kind": AppError.Kind.SERVER_ERROR
	}
	assert_str(detector.fail_line(second, true, "文")).contains("GET /b status=405")
	var third := {
		"serial": 3,
		"method": "POST",
		"endpoint": "/c",
		"http_status": 0,
		"kind": AppError.Kind.NETWORK
	}
	var line: String = detector.fail_line(third, true, "文")
	assert_str(line).contains("POST /c status=0 kind=NETWORK")
	assert_str(line).contains('screen_error="文"')
	# 再試行ボタンが見えていなければ画面の文は添えない
	assert_str(detector.fail_line(third, false, "文")).not_contains("screen_error")


func _run_with_serial(detector: RefCounted, scene: String, seconds: int, serial: int) -> void:
	for t in range(seconds):
		detector.observe(scene, 1.0, serial)
