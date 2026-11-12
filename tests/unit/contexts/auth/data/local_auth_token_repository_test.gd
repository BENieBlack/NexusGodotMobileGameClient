## LocalAuthTokenRepository の単体テスト（user:// の下のテスト専用ディレクトリを使い、終わったら消す）。
extends GdUnitTestSuite

const WORK_DIR := "user://test_auth_tokens/"


func before_test() -> void:
	_remove_dir()


func after_test() -> void:
	_remove_dir()


## 前提: 何も保存していない。操作: 生成。期待: トークンは空（保存トークン無し = sign_up から）。
func test_starts_empty() -> void:
	var repository := LocalAuthTokenRepository.new(WORK_DIR)
	assert_str(repository.access_token()).is_empty()
	assert_str(repository.refresh_token()).is_empty()


## 前提: save_tokens で保存。操作: 別インスタンスで読み直す（アプリの再起動）。
## 期待: トークンが残っている。
func test_tokens_persist_across_instances() -> void:
	LocalAuthTokenRepository.new(WORK_DIR).save_tokens("a", "r")
	var restarted := LocalAuthTokenRepository.new(WORK_DIR)
	assert_str(restarted.access_token()).is_equal("a")
	assert_str(restarted.refresh_token()).is_equal("r")


## 前提: 保存済み + device_id を作成済み。操作: save_tokens("", "")（セッション破棄）→ 再起動。
## 期待: トークンは消えるが、device_id は同じまま残る
## （消すと別の端末として sign_up され、同じ利用者に戻れない）。
func test_clear_keeps_device_id() -> void:
	var repository := LocalAuthTokenRepository.new(WORK_DIR)
	repository.save_tokens("a", "r")
	var device_id := repository.device_id()
	repository.save_tokens("", "")

	var restarted := LocalAuthTokenRepository.new(WORK_DIR)
	assert_str(restarted.refresh_token()).is_empty()
	assert_str(restarted.device_id()).is_equal(device_id)


## 前提: device_id が未保存。操作: device_id を 2 回、別インスタンスでも 1 回。
## 期待: UUID 形式（36 文字）で、いつも同じ値。reset_device_id の後は別の値になる。
func test_device_id_is_stable_and_resettable() -> void:
	var repository := LocalAuthTokenRepository.new(WORK_DIR)
	var device_id := repository.device_id()
	assert_str(device_id).has_length(36)
	assert_str(repository.device_id()).is_equal(device_id)
	assert_str(LocalAuthTokenRepository.new(WORK_DIR).device_id()).is_equal(device_id)

	repository.reset_device_id()
	assert_str(repository.device_id()).is_not_equal(device_id)


## 前提: トークンのファイルが壊れた内容。操作: 生成。期待: 例外にならず、未ログイン扱い（空）。
func test_corrupted_file_is_treated_as_empty() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_DIR))
	var file := FileAccess.open(WORK_DIR + LocalAuthTokenRepository.TOKENS_FILE, FileAccess.WRITE)
	file.store_string("not json")
	file.close()
	assert_str(LocalAuthTokenRepository.new(WORK_DIR).refresh_token()).is_empty()


func _remove_dir() -> void:
	var absolute := ProjectSettings.globalize_path(WORK_DIR)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for file_name in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file_name))
	DirAccess.remove_absolute(absolute)
