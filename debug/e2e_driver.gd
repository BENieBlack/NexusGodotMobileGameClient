## e2e 確認用ドライバー（デバッグ専用のオートロード `E2EDriver`。最後に登録する）。
##
## 目的: 実サーバーに対して「タイトル → 認証 → login → 規約 → ログインボーナス → ホーム」の通しを、
##       人の操作なしで最後まで動かす（client_design.md 7 節）。動画撮影・通しの確認で使う。録画自体はしない。
## 通常起動への影響: 起動引数に `--e2e` 系が無ければ何もしない（_ready で処理を止める）。
##       製品ビルドでは debug/ ごとエクスポートから除外し、project.godot の [autoload] の行も外す。
## 使い方: 引数は Godot の `--` の後ろに付ける（`--` の前でも読む）。
##   godot --path . -- --e2e-case=case1 --e2e-reset
##   godot --headless --path . -- --e2e-case=smoke --e2e-timeout=60
## 引数一覧（`--名前` か `--名前=値`）:
##   --e2e / --e2e=<名前> / --e2e-case=<名前>
##                          ドライバーを有効にする。名前は出力に出すだけのラベル（どれか 1 つが必要）
##   --e2e-reset            起動時にトークンと device_id を消す（新規ユーザーの再現。マスターは消さない）
##   --e2e-fail-login=<種別> login の応答を偽の失敗にする。503（メンテナンス）/ 409 / 429 / network
##   --e2e-fail-count=<回数> 上の失敗を返す回数（既定 1。超えたら本物のサーバーへ送る）
##   --e2e-corrupt-token    規約画面に入る前にアクセストークンを不正値にする（401 → refresh の確認）
##   --e2e-corrupt-refresh  上に加えてリフレッシュトークンも不正値にする（refresh 失敗 → タイトルへ戻る確認）
##   --e2e-no-retry         エラー表示（再試行ボタン）が出たら、押さずに内容を出力して終了する（コード 0）
##   --e2e-shot=<ディレクトリ> 画面ごとにビューポートを PNG に保存する（ヘッドレスでは保存できない）
##   --e2e-dwell=<秒>       画面の操作とエラー表示の再試行の前に止まる秒数（既定 0。録画で画面・エラー文を読めるようにする。
##                          エラーは表示されてから dwell 秒たつまで再試行を押さない。失敗が続いても毎回見える。
##                          429 は dwell と、再試行ボタンが有効になるまでの両方を待つ）
##   --e2e-timeout=<秒>     この秒数で打ち切る（既定 120。コード 1）
## クリックの送り方: 実際のマウス操作に近づけ、移動 → 押下 → 数フレーム → 解放の順に送る（動画で押下の
##   見た目が出る）。座標はビューポート座標で指定し、ウィンドウ座標へ変換して送る（下の make_* と
##   to_window_position。画面より大きい解像度でウィンドウが縮むと、そのままでは別の場所を押すため）。
## 操作（画面ごと。シーンのパスで判定する）:
##   タイトル: 再試行ボタンが見えて押せるなら押す / 規約: 再試行 → 同意ボタンの順に押す
##   ログインボーナス: 画面中央をクリック / ホーム: 2 秒後に終了
## 出力: `E2E: ...` の行に経過、最後に `E2E_RESULT: OK ...`（コード 0）か `E2E_RESULT: TIMEOUT ...`（コード 1）。
##       トークン・秘密鍵・device_id は出さない。
extends Node

## 画面が出てから操作するまでの待ち（秒。録画で表示が見えるように）
const ACTION_DELAY := 1.5
## 画面のスクリーンショットを撮るまでの待ち（秒。レイアウトが落ち着いてから）
const SHOT_DELAY := 1.0
## ホームに入ってから終了するまでの秒数
const HOME_QUIT_DELAY := 2.0
## 押下してから解放するまでのフレーム数（Button が押下の見た目になり、動画に映る長さ）
const PRESS_HOLD_FRAMES := 4

const TITLE_RETRY_PATH := "CenterContainer/PanelContainer/VBoxContainer/RetryButton"
const TITLE_STATUS_PATH := "CenterContainer/PanelContainer/VBoxContainer/StatusLabel"
const AGREEMENT_RETRY_PATH := "VBoxContainer/RetryButton"
const AGREEMENT_AGREE_PATH := "VBoxContainer/AgreeAllButton"
const AGREEMENT_STATUS_PATH := "VBoxContainer/StatusLabel"

## 引数の辞書（キーは "e2e-reset" のように先頭の -- を除いた名前。値の無いものは true）
var _args: Dictionary = {}
var _fail_kind: String = ""
var _fail_remaining: int = 0
var _scene_path: String = ""
## 現在の画面に入ってからの秒数
var _scene_time: float = 0.0
var _elapsed: float = 0.0
var _timeout: float = 120.0
## 各画面で追加で止まる秒数（--e2e-dwell）
var _dwell: float = 0.0
## クリックの送信中（移動 → 押下 → 解放の途中）は次のクリックを始めない
var _is_clicking: bool = false
## このフレームの経過秒（エラー表示の経過時間の更新に使う）
var _error_delta: float = 0.0
## 再試行ボタン（エラー表示）が見えてからの秒数。見えていないときは -1（next_error_time で更新）
var _error_time: float = -1.0
var _quitting: bool = false
## 撮影済みの画面（キー: 画面のパス + 状態）。同じ状態は 1 回だけ撮る
var _shot_keys: Dictionary = {}
var _shot_count: int = 0
## トークンを不正値にしたか。1 回だけにする（毎回壊すと、タイトルへ戻って復旧しても再び壊して無限に戻る）
var _tokens_corrupted: bool = false


func _ready() -> void:
	_args = _parse_args()
	if not (_args.has("e2e") or _args.has("e2e-case")):
		# 通常起動: 何もしない（_process も止める）
		set_process(false)
		return

	print("E2E: ドライバー有効 case=", _args.get("e2e-case", _args.get("e2e", "")), " args=", _args)
	_timeout = float(_args.get("e2e-timeout", 120))
	_dwell = float(_args.get("e2e-dwell", 0))

	# --- 1. 保存の消去（新規ユーザーの再現） ---
	# AppContext は 2 番目のオートロードで、もう組み立て済み。トークンと device_id は保存の窓口から消す
	if _args.has("e2e-reset"):
		var tokens := AppContext.debug_auth_token_repository()
		tokens.save_tokens("", "")
		tokens.reset_device_id()
		print("E2E: トークンと device_id を消しました")

	# --- 2. login の偽の失敗 ---
	if _args.has("e2e-fail-login"):
		_fail_kind = str(_args["e2e-fail-login"])
		_fail_remaining = int(_args.get("e2e-fail-count", 1))
		AppContext.api_client().debug_override = _override_request

	# --- 3. トークンを不正値にする（規約画面がツリーに入る瞬間に差し替える） ---
	if _args.has("e2e-corrupt-token") or _args.has("e2e-corrupt-refresh"):
		get_tree().node_added.connect(_on_node_added)


func _process(delta: float) -> void:
	if _quitting:
		return
	_elapsed += delta
	if _elapsed > _timeout:
		print("E2E_RESULT: TIMEOUT scene=", _scene_path)
		_quit(1)
		return

	var scene := get_tree().current_scene
	if scene == null:
		return
	if scene.scene_file_path != _scene_path:
		_scene_path = scene.scene_file_path
		_scene_time = 0.0
		print("E2E: 画面 ", _scene_path)
	_scene_time += delta
	_error_delta = delta

	match _scene_path:
		SceneRouter.TITLE_SCENE:
			_drive_title(scene)
		SceneRouter.AGREEMENT_SCENE:
			_drive_agreement(scene)
		SceneRouter.LOGIN_BONUS_SCENE:
			_maybe_shot("bonus")
			if _scene_time > ACTION_DELAY + _dwell and not _is_clicking:
				_scene_time = 0.0
				_click_at(get_viewport().get_visible_rect().size / 2.0)
		SceneRouter.HOME_SCENE:
			_maybe_shot("home")
			if _scene_time > HOME_QUIT_DELAY + _dwell:
				print("E2E_RESULT: OK player_id=", AppContext.get_player_id_use_case().handle())
				_quit(0)


# --- 画面ごとの操作 ---


func _drive_title(scene: Node) -> void:
	var retry := scene.get_node_or_null(TITLE_RETRY_PATH) as Button
	var status := scene.get_node_or_null(TITLE_STATUS_PATH) as Label
	if retry != null and retry.visible:
		# エラー表示中。内容を撮ってから、押す（--e2e-no-retry なら内容を出して終了）
		_maybe_shot("title_error_" + str(status.text.hash()))
		if _args.has("e2e-no-retry") and _scene_time > SHOT_DELAY + 0.5:
			print("E2E_RESULT: ERROR_SCREEN title: ", status.text.replace("\n", " / "))
			_quit(0)
			return
	elif status != null:
		_maybe_shot("title")
	_error_time = next_error_time(_error_time, retry != null and retry.visible, _error_delta)
	_click_retry_if_ready(retry)


func _drive_agreement(scene: Node) -> void:
	var retry := scene.get_node_or_null(AGREEMENT_RETRY_PATH) as Button
	var agree := scene.get_node_or_null(AGREEMENT_AGREE_PATH) as Button
	var status := scene.get_node_or_null(AGREEMENT_STATUS_PATH) as Label
	if retry != null and retry.visible:
		_maybe_shot("agreement_error_" + str(status.text.hash()))
		if _args.has("e2e-no-retry") and _scene_time > SHOT_DELAY + 0.5:
			print("E2E_RESULT: ERROR_SCREEN agreement: ", status.text.replace("\n", " / "))
			_quit(0)
			return
	elif agree != null and agree.visible:
		_maybe_shot("agreement")
	# 再試行が出ていればそれを、無ければ同意ボタンを押す
	_error_time = next_error_time(_error_time, retry != null and retry.visible, _error_delta)
	if retry != null and retry.visible:
		_click_retry_if_ready(retry)
	else:
		_click_if_ready(agree)


## 再試行ボタンを押す。通常の条件（_click_if_ready）に加えて、エラーが表示されてから dwell 秒
## たっていること（動画でエラー文が読める。dwell 0 なら従来どおり即）。押したら計り直す
## （次の失敗の表示も dwell 秒見せるため）。429 のボタン無効中は押せないので、その間も表示される。
func _click_retry_if_ready(retry: Button) -> void:
	if retry == null or _error_time < _dwell:
		return
	var before := _scene_time
	_click_if_ready(retry)
	if _scene_time < before:
		# _click_if_ready が押した（_scene_time を 0 に戻した）
		_error_time = -1.0


## ボタンが見えていて押せるとき、画面に出てから ACTION_DELAY 秒後に中心をクリックする。
func _click_if_ready(button: Button) -> void:
	if button == null or not button.is_visible_in_tree() or button.disabled:
		return
	if _scene_time < ACTION_DELAY + _dwell or _is_clicking:
		return
	_scene_time = 0.0
	_click_at(button.get_global_rect().get_center())


## ビューポート座標の位置を左クリックする（移動 → 押下 → PRESS_HOLD_FRAMES フレーム → 解放）。
## 移動を先に送るのは、Control がホバー（マウスの下にある状態）になってから押されるようにするため。
## 押下と解放を同じフレームに送ると、押下の見た目が出ず、環境によって Button が反応しないことがある。
func _click_at(viewport_position: Vector2) -> void:
	_is_clicking = true
	var window_position := to_window_position(
		viewport_position, get_viewport().get_final_transform()
	)
	print("E2E: クリック ", viewport_position)
	Input.parse_input_event(make_motion(window_position))
	await get_tree().process_frame
	Input.parse_input_event(make_button(window_position, true))
	for i in range(PRESS_HOLD_FRAMES):
		await get_tree().process_frame
	Input.parse_input_event(make_button(window_position, false))
	_is_clicking = false


## エラー表示（再試行ボタンが見えている状態）の経過秒を 1 フレーム進める。
## 見えていなければ -1（エラーなし）、見え始めたフレームは 0、見え続けていれば delta だけ増やす。
static func next_error_time(current: float, is_error_visible: bool, delta: float) -> float:
	if not is_error_visible:
		return -1.0
	if current < 0.0:
		return 0.0
	return current + delta


## ビューポート座標をウィンドウ座標へ変換する。Input.parse_input_event の位置はウィンドウ座標として扱われ、
## stretch（canvas_items）の逆変換がかかる。ウィンドウが画面に収まらず縮む（例: 1080x1920 が 1832 の高さ
## になる）と、ビューポート座標のまま送ると別の場所（画面の外を含む）を押してしまう。
static func to_window_position(viewport_position: Vector2, final_transform: Transform2D) -> Vector2:
	return final_transform * viewport_position


## マウスの移動イベント（ボタンは押していない）。
static func make_motion(window_position: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = window_position
	event.global_position = window_position
	event.button_mask = 0
	return event


## 左ボタンの押下・解放イベント。押下中は button_mask に左ボタンが立ち、解放では 0 になる（実機と同じ）。
static func make_button(window_position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = window_position
	event.global_position = window_position
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return event


# --- 偽の失敗・トークンの差し替え ---


## ApiClient.debug_override から呼ばれる。login だけ、指定の回数まで偽の失敗を返す（他は null = 本物を送る）。
func _override_request(_method: String, endpoint: String) -> Variant:
	if endpoint != "/auth/login" or _fail_remaining <= 0:
		return null
	_fail_remaining -= 1
	print("E2E: login を偽の失敗にします kind=", _fail_kind, " 残り=", _fail_remaining)
	match _fail_kind:
		"503":
			var maintenance := ApiResult.make_error(AppError.Kind.MAINTENANCE, 503)
			maintenance.maintenance = {
				"title": "メンテナンス中",
				"message": "ただいまメンテナンス中です",
				"end_at": "2099-01-01 00:00:00",
			}
			return maintenance
		"409":
			return ApiResult.make_error(AppError.Kind.CONFLICT, 409)
		"429":
			var limited := ApiResult.make_error(AppError.Kind.RATE_LIMITED, 429)
			limited.retry_after = 5
			return limited
		_:
			return ApiResult.make_error(AppError.Kind.NETWORK)


## 規約画面がツリーに入った直後（_ready の前）に、トークンを不正値へ差し替える。
func _on_node_added(node: Node) -> void:
	if _tokens_corrupted or node.scene_file_path != SceneRouter.AGREEMENT_SCENE:
		return
	_tokens_corrupted = true
	var tokens := AppContext.debug_auth_token_repository()
	var refresh := tokens.refresh_token()
	if _args.has("e2e-corrupt-refresh"):
		# サーバーが受け付けない 64 桁（refresh の形式）の不正値
		refresh = "x".repeat(64)
	print("E2E: トークンを不正値にします（refresh も: ", _args.has("e2e-corrupt-refresh"), "）")
	tokens.save_tokens("invalid.access.token", refresh)


# --- スクリーンショット ---


## --e2e-shot が指定されていて、画面が落ち着いたら 1 回だけ保存する。
## 同じ状態（key）は 1 回だけ。ヘッドレス（描画なし）では画像が取れないので何もしない。
func _maybe_shot(key: String) -> void:
	if not _args.has("e2e-shot") or _scene_time < SHOT_DELAY:
		return
	var shot_key := _scene_path + "#" + key
	if _shot_keys.has(shot_key):
		return
	_shot_keys[shot_key] = true
	var texture := get_viewport().get_texture()
	if texture == null:
		return
	var directory := str(_args["e2e-shot"])
	DirAccess.make_dir_recursive_absolute(directory)
	_shot_count += 1
	var path := "%s/%02d_%s.png" % [directory, _shot_count, key.get_slice("_", 0)]
	var error := texture.get_image().save_png(path)
	print("E2E: スクリーンショット ", path, " (", error, ")")


# --- 引数・終了 ---


## `--` の後ろ（ユーザー引数）と通常の引数から、--e2e で始まる --key[=value] を集める。
func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if not arg.begins_with("--e2e"):
			continue
		var body: String = arg.substr(2)
		var separator := body.find("=")
		if separator < 0:
			result[body] = true
		else:
			result[body.substr(0, separator)] = body.substr(separator + 1)
	return result


func _quit(code: int) -> void:
	_quitting = true
	get_tree().quit(code)
