## 描画の負荷の指標を、画面が出てから一定秒数ぶん記録して集計する（debug 専用。製品の複製には入らない）。
##
## 目的: 60fps（フレーム 16.6ms）の判断材料を、端末に依らない指標で取る（client_design.md 7 節）。
##       実機（iPhone X）は書き出しテンプレートが無く測れないので、ドロー呼び出し数・オブジェクト数・
##       ノード数（どれも端末に依らない）と、処理時間（TIME_PROCESS。開発機の値なので絶対値では使わず比で見る）を
##       「変更前後の比」で比べる。
## 流れ（E2EDriver が --e2e-frame-probe=<秒> のときだけ使う）:
##   1. 画面が出たフレームで FrameProbe.new(秒) を作る
##   2. 毎フレーム advance(delta) を呼ぶ。1 フレームぶんの指標を溜め、指定秒に達したら true を返す
##   3. true になったら format_line で 1 行にして出力する（平均・最大）
## 注意: Performance の描画統計（ドロー呼び出し・オブジェクト数）は、ヘッドレス（描画しない）では 0 になる。
##       is_headless() が真のときは、出力に「取れない」と書く（0 を本当の値と取り違えないため）。
##       また --write-movie（Movie Maker）は固定フレームで時間が歪むので併用しない。
extends RefCounted

## 集計する指標の名前（出力の順）。値の出どころは sample_now
const KEYS: Array[String] = ["process_ms", "draw_calls", "objects", "nodes"]

## 記録する秒数と、これまでに進んだ秒数
var duration: float = 2.0
var _elapsed: float = 0.0
## 1 フレームぶんの指標の辞書の並び（キーは KEYS）
var _samples: Array[Dictionary] = []


func _init(seconds: float = 2.0) -> void:
	duration = seconds


## 1 フレーム進める。指標を 1 つ溜め、指定秒に達したら true（記録の終わり）。
func advance(delta: float) -> bool:
	_samples.append(sample_now())
	_elapsed += delta
	return _elapsed >= duration


## 溜めたフレーム数。
func frames() -> int:
	return _samples.size()


## 集計結果を返す（溜めた指標から）。
func result() -> Dictionary:
	return summarize(_samples)


## いまの指標を 1 つ取る。
## process_ms: 直前のフレームの処理時間（ミリ秒。Performance は秒で返すので 1000 倍する）
## draw_calls / objects: 直前のフレームの描画の呼び出し数・描いたオブジェクト数（ヘッドレスでは 0）
## nodes: シーンツリーにあるノードの数
static func sample_now() -> Dictionary:
	return {
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	}


## 指標の並びを「キー → {avg, max}」にまとめる（純粋関数。テストできる）。
## 空の並びは、全キーを 0 で返す（0 除算を避ける）。
static func summarize(samples: Array[Dictionary]) -> Dictionary:
	var out := {}
	for key in KEYS:
		var total := 0.0
		var peak := 0.0
		for sample in samples:
			var value := float(sample.get(key, 0.0))
			total += value
			peak = maxf(peak, value)
		var average := 0.0 if samples.is_empty() else total / samples.size()
		out[key] = {"avg": average, "max": peak}
	return out


## 出力の 1 行にする。例: `E2E_PROBE: label=home frames=118 process_ms=avg 1.20/max 3.40 draw_calls=avg ...`
## ヘッドレスのときは末尾に `render=unavailable(headless)` を付ける（描画統計が 0 になる旨）。
static func format_line(label: String, frames: int, summary: Dictionary, headless: bool) -> String:
	var parts: Array[String] = []
	for key in KEYS:
		var entry: Dictionary = summary.get(key, {"avg": 0.0, "max": 0.0})
		parts.append("%s=avg %.2f/max %.2f" % [key, entry["avg"], entry["max"]])
	var line := "E2E_PROBE: label=%s frames=%d %s" % [label, frames, " ".join(parts)]
	if headless:
		line += " render=unavailable(headless)"
	return line


## ヘッドレス（描画しない）か。描画統計が取れないかどうかの判定に使う。
static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"
