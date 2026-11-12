## 認証（sign_in / sign_up の振り分け）の UseCase（client_design.md 3-3、D10）。
##
## 目的: タイトルの AUTH 段階で呼ぶ。端末に保存トークンがあれば sign_in、無ければ sign_up を呼び、
##       サーバーと端末の状態が食い違ったとき（10002 / 10004）に、もう一方へ 1 回だけ切り替える。
## 流れ（handle）:
##   1. 保存トークンの有無で最初に呼ぶ API を決める（あり → sign_in、なし → sign_up）
##   2. 業務エラー（BUSINESS）が次のときだけ、もう一方の API へ 1 回切り替える
##      - sign_in が 10002（端末がサーバーに未登録）→ sign_up
##      - sign_up が 10004（端末が登録済み）→ sign_in（device_id は保存済みの値なので同じ利用者になる。要件 F1）
##   3. 切り替えは 1 回で打ち切る。切り替え先も失敗したら、その失敗をそのまま返す
##      （サーバーの状態が矛盾していても無限に往復しない。BUSINESS は画面に表示される）
##   4. 成功したらトークンを保存する（ApiClient が以後の Authorization・refresh に使う）
## 失敗の扱い: 例外にせず Result.failure(AppError) で返す。再試行は呼び出し元の presenter が決める
##   （sign_up / sign_in の再試行に冪等キーは使わない。3-4）。
## 依存: AuthRepository（契約）と ApiAuthProvider（core の契約。トークンの保存と有無）だけ。
class_name AuthenticateUseCase
extends RefCounted

## sign_in で端末が未登録のときのコード（サーバー api.md。PLAYER_NOT_FOUND）
const ERROR_PLAYER_NOT_FOUND := 10002
## sign_up で端末が登録済みのときのコード（DEVICE_ALREADY_EXISTS）
const ERROR_DEVICE_ALREADY_EXISTS := 10004

var _auth_repository: AuthRepository
var _token_store: ApiAuthProvider


func _init(auth_repository: AuthRepository, token_store: ApiAuthProvider) -> void:
	_auth_repository = auth_repository
	_token_store = token_store


## 認証する。呼び出し側は await する。
func handle() -> Result:
	# --- 1. 最初に呼ぶ API を決める ---
	# 保存トークンの有無で決める（要件どおり）。refresh_token が残っていれば既存端末とみなす
	var has_token := _token_store.refresh_token() != "" or _token_store.access_token() != ""
	var first_is_sign_in := has_token
	var result := await _call(first_is_sign_in)

	# --- 2. 食い違いのときだけ、もう一方へ 1 回切り替える ---
	if not result.ok and result.error.kind == AppError.Kind.BUSINESS:
		var code := result.error.error_code
		var should_switch := (
			(first_is_sign_in and code == ERROR_PLAYER_NOT_FOUND)
			or (not first_is_sign_in and code == ERROR_DEVICE_ALREADY_EXISTS)
		)
		if should_switch:
			# --- 3. 切り替えは 1 回だけ。結果が失敗でも、ここで打ち切って返す ---
			result = await _call(not first_is_sign_in)

	if not result.ok:
		return Result.failure(result.error)

	# --- 4. トークンを保存する ---
	_token_store.save_tokens(result.session.access_token, result.session.refresh_token)
	return Result.success()


func _call(use_sign_in: bool) -> AuthSessionResult:
	if use_sign_in:
		return await _auth_repository.sign_in()
	return await _auth_repository.sign_up()
