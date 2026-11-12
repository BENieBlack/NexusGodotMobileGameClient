## トークンと device_id の端末内保存（ApiAuthProvider の実装。client_design.md 2-1）。
##
## 目的: ApiClient（core）が Authorization と refresh に使うトークンの供給元、かつ保存先。
##       AuthenticateUseCase が sign_in / sign_up の振り分け（保存トークンの有無）に使い、
##       AuthApiRepository が device_id を取り出す。core は auth を参照しないので、契約 ApiAuthProvider
##       （core/domain）を実装して AppContext が ApiClient に渡す。
## 保存する場所（storage_dir の下。既定 user://）:
##   auth_tokens.json  {"access_token": String, "refresh_token": String}。トークンが空なら、ファイルを消す
##   device_id.save    device_id の文字列だけ（旧 auth_service.gd と同じ場所・形式。旧版の端末 ID を引き継ぐ）
## device_id をトークンと別のファイルにする理由: セッションを破棄（session_expired）してもトークンだけを消し、
##   device_id は残すため。消すと別の端末として sign_up され、同じ利用者に戻れない（要件 F1）。
## 書き込みは一時ファイル（.tmp）に書いてから rename で確定する（書きかけのファイルで壊れないように）。
## 注意: トークンは秘密情報。ログや print に出さない。永続化は平文（暗号化・Keychain は別機能）。
class_name LocalAuthTokenRepository
extends ApiAuthProvider

const TOKENS_FILE := "auth_tokens.json"
const DEVICE_ID_FILE := "device_id.save"

var _storage_dir: String
var _access_token: String = ""
var _refresh_token: String = ""
var _device_id: String = ""


## storage_dir は保存先のディレクトリ（テストで実機の user:// を汚さないよう差し替えられる）。
## 起動時に保存済みのトークンを読み込む。
func _init(storage_dir: String = "user://") -> void:
	_storage_dir = storage_dir if storage_dir.ends_with("/") else storage_dir + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_storage_dir))
	_load_tokens()


func access_token() -> String:
	return _access_token


func refresh_token() -> String:
	return _refresh_token


## トークンを保存する。両方が空なら破棄（ファイルも消す）。
## 書き込みに失敗してもメモリには保持する（この起動中は使え、次回起動で sign_in / sign_up からやり直せる）。
func save_tokens(p_access_token: String, p_refresh_token: String) -> void:
	_access_token = p_access_token
	_refresh_token = p_refresh_token
	var path := _storage_dir + TOKENS_FILE
	if _access_token == "" and _refresh_token == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var text := JSON.stringify({"access_token": _access_token, "refresh_token": _refresh_token})
	if not _write_atomically(path, text):
		push_warning("トークンを保存できませんでした")


## 端末の識別子。保存済みならその値、無ければ UUID v4 を作って保存する。
## 保存に失敗しても、この起動中は同じ値を返す。
func device_id() -> String:
	if _device_id != "":
		return _device_id
	var path := _storage_dir + DEVICE_ID_FILE
	if FileAccess.file_exists(path):
		_device_id = FileAccess.get_file_as_string(path).strip_edges()
	if _device_id == "":
		_device_id = IdempotencyKey.generate()
		if not _write_atomically(path, _device_id):
			push_warning("device_id を保存できませんでした")
	return _device_id


## device_id を消す（デバッグ用。次の device_id() で新しい端末として作り直される）。
func reset_device_id() -> void:
	_device_id = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_storage_dir + DEVICE_ID_FILE))


## 保存済みのトークンを読む。ファイルが無い・壊れているときは空のまま（未ログイン扱い）。
func _load_tokens() -> void:
	var path := _storage_dir + TOKENS_FILE
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	_access_token = str(parsed.get("access_token", ""))
	_refresh_token = str(parsed.get("refresh_token", ""))


## path に text を書く（一時ファイル → rename）。成功なら true。
func _write_atomically(path: String, text: String) -> bool:
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	# close の後で書き込みエラーを見る（バッファは close で flush される）
	file.close()
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	var write_ok := file.get_error() == OK
	if write_ok:
		write_ok = (
			DirAccess.rename_absolute(absolute_temp, ProjectSettings.globalize_path(path)) == OK
		)
	if not write_ok:
		DirAccess.remove_absolute(absolute_temp)
	return write_ok
