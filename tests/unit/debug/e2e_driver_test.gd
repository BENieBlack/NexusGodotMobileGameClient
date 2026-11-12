## e2e ドライバーのクリック入力の組み立てのテスト（debug/e2e_driver.gd の static 関数）。
##
## 規約画面の同意ボタンが押せなかった原因は、ウィンドウが画面に収まらず縮んだとき（1080x1920 が 1832 の高さ）、
## ビューポート座標をそのまま送ると、ウィンドウの外（y=1856）を押していたこと。座標変換と、
## 実際のマウスに近いイベント（移動・押下・解放）の組み立てを確かめる。ドライバーはオートロードなので
## インスタンスは作らず、スクリプトの static 関数を直接呼ぶ。
extends GdUnitTestSuite

const DRIVER := "res://debug/e2e_driver.gd"


## 前提: stretch で 0.95 倍に縮み、左に 25px 余白がある変換（実際に出た値）。操作: 変換。
## 期待: ビューポートの (540, 1856) が、ウィンドウの高さ 1832 の内側に入る（押せる位置になる）。
func test_to_window_position_applies_stretch_transform() -> void:
	var transform := Transform2D(Vector2(0.953704, 0), Vector2(0, 0.954167), Vector2(25, 0))
	var position: Vector2 = load(DRIVER).to_window_position(Vector2(540, 1856), transform)
	assert_float(position.y).is_less(1832.0)
	assert_float(position.x).is_equal_approx(540 * 0.953704 + 25, 0.01)


## 前提: 変換なし（録画時などウィンドウ = ビューポート）。期待: 座標は変わらない。
func test_to_window_position_identity() -> void:
	var position: Vector2 = load(DRIVER).to_window_position(Vector2(540, 960), Transform2D.IDENTITY)
	assert_vector(position).is_equal(Vector2(540, 960))


## 前提: 押下と解放のイベントを作る。期待: 左ボタン・指定位置で、押下は button_mask に左が立ち、
## 解放は 0（実機の入力と同じ。Button は mask 付きの押下の後の解放で pressed を出す）。
func test_button_events_match_real_mouse() -> void:
	var down: InputEventMouseButton = load(DRIVER).make_button(Vector2(10, 20), true)
	var up: InputEventMouseButton = load(DRIVER).make_button(Vector2(10, 20), false)
	assert_int(down.button_index).is_equal(MOUSE_BUTTON_LEFT)
	assert_bool(down.pressed).is_true()
	assert_int(down.button_mask).is_equal(MOUSE_BUTTON_MASK_LEFT)
	assert_vector(down.position).is_equal(Vector2(10, 20))
	assert_bool(up.pressed).is_false()
	assert_int(up.button_mask).is_equal(0)


## 前提: 移動イベントを作る。期待: ボタンを押していない移動（ホバーのため、押下の前に送る）。
func test_motion_event_has_no_buttons() -> void:
	var motion: InputEventMouseMotion = load(DRIVER).make_motion(Vector2(5, 6))
	assert_vector(motion.position).is_equal(Vector2(5, 6))
	assert_int(motion.button_mask).is_equal(0)


## 前提: エラー表示（再試行ボタン）が見え始め → 見え続け → 消える（押して再試行中）→ 再び見える。
## 期待: 見え始めは 0、続けば delta ずつ増え、消えたら -1、再び見えたら 0 から数え直す
## （失敗が続いても毎回 dwell 秒見せられる。dwell 前に押さないための経過秒の根拠）。
func test_next_error_time_restarts_for_each_error() -> void:
	var driver: GDScript = load(DRIVER)
	var t: float = driver.next_error_time(-1.0, true, 0.1)
	assert_float(t).is_equal(0.0)
	t = driver.next_error_time(t, true, 0.5)
	t = driver.next_error_time(t, true, 0.5)
	assert_float(t).is_equal_approx(1.0, 0.0001)
	t = driver.next_error_time(t, false, 0.5)
	assert_float(t).is_equal(-1.0)
	assert_float(driver.next_error_time(t, true, 0.5)).is_equal(0.0)


## 前提: --e2e-case 付きの引数。操作: debug ビルドか否かで判定。
## 期待: debug ビルドでは有効、製品ビルド（debug でない）では引数があっても無効（混入しても動かない）。
func test_is_enabled_only_in_debug_build() -> void:
	var args := {"e2e-case": "probe"}
	assert_bool(load(DRIVER).is_enabled(args, true)).is_true()
	assert_bool(load(DRIVER).is_enabled(args, false)).is_false()
	assert_bool(load(DRIVER).is_enabled({"e2e": true}, true)).is_true()


## 前提: --e2e 系でない引数（--e2e-reset だけ）か、引数なし。期待: debug ビルドでも無効（通常起動は何もしない）。
func test_is_enabled_requires_e2e_argument() -> void:
	assert_bool(load(DRIVER).is_enabled({}, true)).is_false()
	assert_bool(load(DRIVER).is_enabled({"e2e-reset": true}, true)).is_false()
