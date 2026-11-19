## FrameProbe（描画の指標の記録・集計。debug/frame_probe.gd）と、ドライバーの引数・ギャラリーの純粋関数のテスト。
## 集計と出力の形を単体で守る（描画統計そのものはヘッドレスでは取れないので、取れる値は実行で確かめる）。
extends GdUnitTestSuite

const PROBE := "res://debug/frame_probe.gd"
const DRIVER := "res://debug/e2e_driver.gd"
const GALLERY := "res://debug/icon_gallery.gd"


## 前提: 3 フレームぶんの指標。期待: キーごとの平均と最大。
func test_summarize_average_and_max() -> void:
	var samples: Array[Dictionary] = [
		{"process_ms": 1.0, "draw_calls": 10, "objects": 20, "nodes": 30},
		{"process_ms": 3.0, "draw_calls": 20, "objects": 40, "nodes": 30},
		{"process_ms": 2.0, "draw_calls": 30, "objects": 60, "nodes": 30},
	]
	var summary: Dictionary = load(PROBE).summarize(samples)
	assert_float(summary["process_ms"]["avg"]).is_equal_approx(2.0, 0.001)
	assert_float(summary["process_ms"]["max"]).is_equal_approx(3.0, 0.001)
	assert_float(summary["draw_calls"]["avg"]).is_equal_approx(20.0, 0.001)
	assert_float(summary["draw_calls"]["max"]).is_equal_approx(30.0, 0.001)
	assert_float(summary["nodes"]["max"]).is_equal_approx(30.0, 0.001)


## 前提: 1 フレームも無い。期待: 0 除算にならず、全キーが 0。
func test_summarize_empty() -> void:
	var empty: Array[Dictionary] = []
	var summary: Dictionary = load(PROBE).summarize(empty)
	for key: String in load(PROBE).KEYS:
		assert_float(summary[key]["avg"]).is_equal(0.0)
		assert_float(summary[key]["max"]).is_equal(0.0)


## 前提: 0.1 秒の窓に 0.04 秒のフレームを流す。期待: 3 フレーム目（0.12 秒）で記録が終わり、フレーム数が数えられる。
func test_advance_finishes_after_duration() -> void:
	var probe: RefCounted = load(PROBE).new(0.1)
	assert_bool(probe.advance(0.04)).is_false()
	assert_bool(probe.advance(0.04)).is_false()
	assert_bool(probe.advance(0.04)).is_true()
	assert_int(probe.frames()).is_equal(3)
	assert_dict(probe.result()).contains_keys(["process_ms", "draw_calls", "objects", "nodes"])


## 前提: 出力の 1 行。期待: ラベル・フレーム数・各指標が入り、ヘッドレスのときだけ「取れない」の印が付く。
func test_format_line() -> void:
	var samples: Array[Dictionary] = [
		{"process_ms": 2.0, "draw_calls": 12, "objects": 80, "nodes": 29}
	]
	var summary: Dictionary = load(PROBE).summarize(samples)
	var line: String = load(PROBE).format_line("home", 1, summary, false)
	assert_str(line).starts_with("E2E_PROBE: label=home frames=1 ")
	assert_str(line).contains("draw_calls=avg 12.00/max 12.00")
	assert_str(line).not_contains("unavailable")
	assert_str(load(PROBE).format_line("home", 1, summary, true)).contains(
		"render=unavailable(headless)"
	)


## 前提: --e2e-frame-probe の値。期待: 数値は秒、値なし・数値でない・負・0 は 0（記録しない）。
func test_frame_probe_seconds_argument() -> void:
	var driver: GDScript = load(DRIVER)
	assert_float(driver.frame_probe_seconds({"e2e-frame-probe": "2"})).is_equal(2.0)
	assert_float(driver.frame_probe_seconds({"e2e-frame-probe": "1.5"})).is_equal(1.5)
	assert_float(driver.frame_probe_seconds({"e2e-frame-probe": true})).is_equal(0.0)
	assert_float(driver.frame_probe_seconds({"e2e-frame-probe": "abc"})).is_equal(0.0)
	assert_float(driver.frame_probe_seconds({"e2e-frame-probe": "-3"})).is_equal(0.0)
	assert_float(driver.frame_probe_seconds({})).is_equal(0.0)


## 前提: 表のキーとマスターの ID。期待: マスターに在って絵が無い ID だけを返す（ギャラリーが赤く出す対象）。
func test_gallery_missing_ids() -> void:
	var keys: Array[String] = ["items/coin", "items/gold", "fallback/unknown"]
	var ids: Array[String] = ["coin", "gold", "new_item"]
	var missing: Array[String] = load(GALLERY).missing_ids(keys, ids)
	assert_array(missing).contains_exactly(["new_item"])
	var none: Array[String] = ["coin"]
	assert_array(load(GALLERY).missing_ids(keys, none)).is_empty()
