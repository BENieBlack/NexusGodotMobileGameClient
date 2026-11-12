## ApiConfig の単体テスト（環境変数 → project.godot の [nexus] → 既定値の優先順）。
extends GdUnitTestSuite

var _saved_api_setting: Variant
var _saved_master_setting: Variant


## 実行前に、ProjectSettings の現在値を退避し、環境変数と設定を空にする（テスト間・実環境の影響を断つ）。
func before_test() -> void:
	_saved_api_setting = ProjectSettings.get_setting(ApiConfig.SETTING_API_BASE_URL, null)
	_saved_master_setting = ProjectSettings.get_setting(ApiConfig.SETTING_MASTER_BASE_URL, null)
	OS.unset_environment(ApiConfig.ENV_API_BASE_URL)
	OS.unset_environment(ApiConfig.ENV_MASTER_BASE_URL)
	ProjectSettings.set_setting(ApiConfig.SETTING_API_BASE_URL, null)
	ProjectSettings.set_setting(ApiConfig.SETTING_MASTER_BASE_URL, null)


## 実行後に、退避した設定を戻し、環境変数を消す。
func after_test() -> void:
	OS.unset_environment(ApiConfig.ENV_API_BASE_URL)
	OS.unset_environment(ApiConfig.ENV_MASTER_BASE_URL)
	ProjectSettings.set_setting(ApiConfig.SETTING_API_BASE_URL, _saved_api_setting)
	ProjectSettings.set_setting(ApiConfig.SETTING_MASTER_BASE_URL, _saved_master_setting)


## 前提: 環境変数も設定も無い。操作: 両方の URL を読む。期待: 既定値（ローカルの :8090 と :8091）。
func test_defaults_when_nothing_is_set() -> void:
	assert_str(ApiConfig.api_base_url()).is_equal("http://localhost:8090/api")
	assert_str(ApiConfig.master_base_url()).is_equal("http://localhost:8091")


## 前提: [nexus] の設定だけある（末尾に / 付き）。操作: 読む。
## 期待: 設定値が既定値に勝ち、末尾の / は除かれる（"/auth/..." を連結して // にならないため）。
func test_project_setting_overrides_default_and_trims_slash() -> void:
	ProjectSettings.set_setting(ApiConfig.SETTING_API_BASE_URL, "http://example.test/api/")
	ProjectSettings.set_setting(ApiConfig.SETTING_MASTER_BASE_URL, "http://cdn.test/")
	assert_str(ApiConfig.api_base_url()).is_equal("http://example.test/api")
	assert_str(ApiConfig.master_base_url()).is_equal("http://cdn.test")


## 前提: 設定と環境変数の両方がある。操作: 読む。期待: 環境変数が勝つ。
## 検証時に、書き換えずに向き先を変えられる（設計 2-1）ことを守る。
func test_environment_overrides_project_setting() -> void:
	ProjectSettings.set_setting(ApiConfig.SETTING_API_BASE_URL, "http://setting.test/api")
	OS.set_environment(ApiConfig.ENV_API_BASE_URL, "http://env.test/api")
	OS.set_environment(ApiConfig.ENV_MASTER_BASE_URL, "http://localhost:9")
	assert_str(ApiConfig.api_base_url()).is_equal("http://env.test/api")
	assert_str(ApiConfig.master_base_url()).is_equal("http://localhost:9")


## 前提: 環境変数が空文字。操作: 読む。期待: 未設定として扱い、設定値（無ければ既定値）に進む。
## 空で渡されても接続先が空にならないことを守る。
func test_empty_environment_is_ignored() -> void:
	OS.set_environment(ApiConfig.ENV_API_BASE_URL, "")
	assert_str(ApiConfig.api_base_url()).is_equal("http://localhost:8090/api")
