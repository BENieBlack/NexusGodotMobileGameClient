## タイトル画面の presenter（client_design.md 1-1・1-2・3-2）。
##
## 目的: 起動直後に「マスターデータ確認 → 認証 → login」を自動で進め、成功したら規約画面へ進む。
##       失敗したら、画面にエラー文と「再試行」ボタンを出し、失敗した段階からやり直せるようにする。
##       画面の制御（段階の進行・表示・遷移）だけを持ち、通信や保存は UseCase に任せる。
## 流れ（_run。段階は Stage）:
##   1. MASTER : check_master_data_use_case。失敗でも次へ進む（保存済みのデータで続行）が、通知を出し、
##               _master_failed を立てる（再試行の起点を決めるため）
##   2. AUTH   : authenticate_use_case（sign_in / sign_up の振り分けは UseCase の中）
##   3. LOGIN  : login_use_case（冪等キー付き）。キーは LOGIN 段階に入るときに作って保持する
##   4. 完了   : リアルタイム通知を始め、「ログイン成功!」→ 規約画面へ
## 再試行（_on_retry_pressed）: 失敗した段階からやり直す（成功済みの段階は繰り返さない）。ただし MASTER が
##   FAILED だったときは、どの段階（AUTH・LOGIN）の失敗でも MASTER から再実行する（初回は master_hash が空で、
##   サーバーからの更新要求も来ないため、ここが再取得の唯一の手段。設計 1-2）。LOGIN 失敗の再試行でも
##   認証からやり直すことになるが、意図どおり。冪等キーは保持するので、同じキーで login を再送できる。
##   SESSION_EXPIRED（LOGIN 中に refresh が失敗してログアウト）は AUTH から。
## 画面の破棄: await（タイマー・UseCase）から戻ったとき、遷移・破棄済み（ツリーの外）なら何もせず終わる。
##   破棄済みの画面のラベルや router を触らないため（各 await の直後に _is_alive で確かめる）。
## 冪等キー（設計 3-4）: 再送してよいかは IdempotencyKey.can_reuse で決める。BUSINESS（業務エラーも
##   サーバーに保存される）なら作り直し、NETWORK・409・503 などは同じキーで再送する。成功・タイトルへ戻るときも作り直す。
## 依存: UseCase だけを呼ぶ（API・保存を直接呼ばない）。遷移と通知は、既定ではオートロードの SceneRouter / Toast。
##   テストでは setup() で偽物を渡す（_ready より前に呼ぶ）。
class_name TitlePresenter
extends Control

## 起動の段階。失敗した段階を覚えて、そこから再開する
enum Stage { MASTER, AUTH, LOGIN, DONE }

## 起動してから最初の処理までの待ち（秒）。タイトルを見せる演出（設計 3-2）
var start_delay_sec: float = 0.5
## マスター更新失敗の通知を状態表示に出しておく秒数（設計 5 節）
var master_notice_sec: float = 2.0
## 「ログイン成功!」を見せてから規約画面へ進むまでの秒数
var success_hold_sec: float = 0.5

var _stage: Stage = Stage.MASTER
var _master_failed: bool = false
var _login_key: String = ""
var _is_running: bool = false

var _check_master_data: CheckMasterDataUseCase
var _authenticate: AuthenticateUseCase
var _login: LoginUseCase
var _get_player_id: GetPlayerIdUseCase
var _get_access_token: GetAccessTokenUseCase
var _reverb_endpoint: ReverbEndpoint
var _router: Object
var _toast: Object
var _is_configured: bool = false

@onready var _status_label: Label = $CenterContainer/PanelContainer/VBoxContainer/StatusLabel
@onready var _retry_button: Button = $CenterContainer/PanelContainer/VBoxContainer/RetryButton


## UseCase と、遷移・通知の相手を渡す。_ready より前（add_child の前）に呼ぶとその値を使い、
## 呼ばなければ _ready がオートロード（AppContext / SceneRouter / Toast）から取る。
func setup(
	check_master_data: CheckMasterDataUseCase,
	authenticate: AuthenticateUseCase,
	login: LoginUseCase,
	get_player_id: GetPlayerIdUseCase,
	get_access_token: GetAccessTokenUseCase,
	reverb_endpoint: ReverbEndpoint,
	router: Object,
	toast: Object
) -> void:
	_check_master_data = check_master_data
	_authenticate = authenticate
	_login = login
	_get_player_id = get_player_id
	_get_access_token = get_access_token
	_reverb_endpoint = reverb_endpoint
	_router = router
	_toast = toast
	_is_configured = true


func _ready() -> void:
	if not _is_configured:
		setup(
			AppContext.check_master_data_use_case(),
			AppContext.authenticate_use_case(),
			AppContext.login_use_case(),
			AppContext.get_player_id_use_case(),
			AppContext.get_access_token_use_case(),
			AppContext.reverb_endpoint(),
			SceneRouter,
			Toast
		)
	_retry_button.pressed.connect(_on_retry_pressed)
	_status_label.text = "ロード中..."
	ErrorView.hide_retry(_retry_button)

	# タイトルを少し見せてから始める（演出）
	if start_delay_sec > 0.0:
		await get_tree().create_timer(start_delay_sec).timeout
		if not _is_alive():
			return
	_run()


## 現在の段階から順に進める。失敗したらエラーを表示して止まる（再試行ボタンで再開）。
## 二重に走らないようにする（ボタンの連打・再試行中の再呼び出し）。
func _run() -> void:
	if _is_running:
		return
	_is_running = true
	ErrorView.hide_retry(_retry_button)

	# --- 1. MASTER ---
	if _stage == Stage.MASTER:
		await _run_master_stage()
		if not _is_alive():
			_is_running = false
			return
		_stage = Stage.AUTH

	# --- 2. AUTH ---
	if _stage == Stage.AUTH:
		var auth_error := await _run_auth_stage()
		if not _is_alive():
			_is_running = false
			return
		if auth_error != null:
			_fail(auth_error)
			return
		_stage = Stage.LOGIN

	# --- 3. LOGIN ---
	if _stage == Stage.LOGIN:
		var login_error := await _run_login_stage()
		if not _is_alive():
			_is_running = false
			return
		if login_error != null:
			_fail(login_error)
			return
		_stage = Stage.DONE

	# --- 4. 完了 ---
	await _finish()


## MASTER 段階。失敗しても止めず、通知だけ出して続ける（設計 5 節 D8）。
func _run_master_stage() -> void:
	_status_label.text = "マスターデータを確認中..."
	# 進捗の表示は、この呼び出しの間だけ受ける（UseCase は長生きなので、つなぎっぱなしにしない）
	_check_master_data.download_progress.connect(_on_download_progress)
	var result := await _check_master_data.handle()
	_disconnect_progress()
	if not _is_alive():
		return

	_master_failed = result.status == CheckMasterDataResult.Status.FAILED
	if not _master_failed:
		return
	var notice := "マスターデータを更新できませんでした。保存済みのデータで続行します"
	_status_label.text = notice
	_toast.show_toast("マスターデータ", "更新できませんでした。保存済みのデータで続行します")
	if master_notice_sec > 0.0:
		await get_tree().create_timer(master_notice_sec).timeout


## AUTH 段階。成功なら null、失敗なら AppError を返す。
func _run_auth_stage() -> AppError:
	# 新規か既存かで文言を分ける（UseCase が handle の中で決めるのと同じ判定）
	_status_label.text = "新規登録中..." if _authenticate.is_new_user() else "ログイン中..."
	var result := await _authenticate.handle()
	return null if result.ok else result.error


## LOGIN 段階。成功なら null、失敗なら AppError を返す。
func _run_login_stage() -> AppError:
	_status_label.text = "ゲームデータを取得中..."
	# 冪等キーは LOGIN 段階に入るときに作る。再試行で同じ段階から再開するときは、残っていれば使い回す
	if _login_key == "":
		_login_key = IdempotencyKey.generate()
	var result := await _login.handle(_login_key)
	if result.ok:
		_login_key = ""
		return null
	# 再送してよい失敗（通信断・409・503 など）はキーを残す。業務エラー（299）は結果が保存されるので作り直す
	if not IdempotencyKey.can_reuse(result.error.kind):
		_login_key = ""
	return result.error


## 完了。通知を始め、成功を見せて規約画面へ進む。
func _finish() -> void:
	# リアルタイム通知（Reverb）は対象外の機能だが、旧実装と同じくここで始める。
	# 接続できなくても画面の進行には影響しない（Toast 側が再接続を試みるだけ）
	_toast.connect_to_reverb(_get_player_id.handle(), _get_access_token.handle(), _reverb_endpoint)
	_status_label.text = "ログイン成功!"
	if success_hold_sec > 0.0:
		await get_tree().create_timer(success_hold_sec).timeout
		if not _is_alive():
			_is_running = false
			return
	_is_running = false
	_router.goto_agreement()


## 画面がまだツリーの中にあるか。await の後に、遷移・破棄済みの画面を触らないための確認。
func _is_alive() -> bool:
	return is_inside_tree()


## 進捗表示の接続を外す。UseCase は長生きなので画面より先に消えない。つながっているときだけ外す
## （画面の破棄後に走っても、未接続の disconnect でエラーにならない）。
func _disconnect_progress() -> void:
	if _check_master_data.download_progress.is_connected(_on_download_progress):
		_check_master_data.download_progress.disconnect(_on_download_progress)


func _exit_tree() -> void:
	# マスター確認の途中で画面が外れたとき、UseCase に残る接続を片付ける
	if _check_master_data != null:
		_disconnect_progress()


## 失敗した段階で止まり、エラー文と再試行ボタンを出す。
func _fail(error: AppError) -> void:
	# SESSION_EXPIRED は LOGIN 中に refresh が失敗して、トークンが破棄された状態。AUTH からやり直す。
	# 冪等キーも作り直す（タイトルへ戻るのと同じ。設計 3-4）
	if error.kind == AppError.Kind.SESSION_EXPIRED:
		_stage = Stage.AUTH
		_login_key = ""
	_is_running = false
	ErrorView.show_error(_status_label, _retry_button, error)


## 再試行ボタン。失敗した段階から再開する。
func _on_retry_pressed() -> void:
	# MASTER が FAILED だったなら、失敗した段階が AUTH でも LOGIN でも MASTER 段階から再実行する
	# （設計 1-2。再取得の唯一の手段。LOGIN 失敗でも認証からやり直すが、冪等キーは _login_key に残る）
	if _master_failed:
		_stage = Stage.MASTER
	_run()


## マスターの更新の進捗を表示する（「マスターデータを更新中 (n/m)」）。バーは作らない。
func _on_download_progress(current: int, total: int, _table_name: String) -> void:
	_status_label.text = "マスターデータを更新中 (%d/%d)" % [current, total]
