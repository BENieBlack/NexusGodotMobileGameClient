## ApiConfig の単体テスト（環境変数 → project.godot の [nexus] → 既定値の優先順）。
extends GdUnitTestSuite

const REVERB_ENVS := [
	ApiConfig.ENV_REVERB_HOST,
	ApiConfig.ENV_REVERB_PORT,
	ApiConfig.ENV_REVERB_SCHEME,
	ApiConfig.ENV_REVERB_APP_KEY,
]
const REVERB_SETTINGS := [
	ApiConfig.SETTING_REVERB_HOST,
	ApiConfig.SETTING_REVERB_PORT,
	ApiConfig.SETTING_REVERB_SCHEME,
	ApiConfig.SETTING_REVERB_APP_KEY,
]

var _saved_api_setting: Variant
var _saved_master_setting: Variant
var _saved_reverb_settings: Array = []


## 実行前に、ProjectSettings の現在値を退避し、環境変数と設定を空にする（テスト間・実環境の影響を断つ）。
func before_test() -> void:
	_saved_api_setting = ProjectSettings.get_setting(ApiConfig.SETTING_API_BASE_URL, null)
	_saved_master_setting = ProjectSettings.get_setting(ApiConfig.SETTING_MASTER_BASE_URL, null)
	OS.unset_environment(ApiConfig.ENV_API_BASE_URL)
	OS.unset_environment(ApiConfig.ENV_MASTER_BASE_URL)
	ProjectSettings.set_setting(ApiConfig.SETTING_API_BASE_URL, null)
	ProjectSettings.set_setting(ApiConfig.SETTING_MASTER_BASE_URL, null)
	_saved_reverb_settings = []
	for name in REVERB_SETTINGS:
		_saved_reverb_settings.append(ProjectSettings.get_setting(name, null))
		ProjectSettings.set_setting(name, null)
	for name in REVERB_ENVS:
		OS.unset_environment(name)


## 実行後に、退避した設定を戻し、環境変数を消す。
func after_test() -> void:
	OS.unset_environment(ApiConfig.ENV_API_BASE_URL)
	OS.unset_environment(ApiConfig.ENV_MASTER_BASE_URL)
	ProjectSettings.set_setting(ApiConfig.SETTING_API_BASE_URL, _saved_api_setting)
	ProjectSettings.set_setting(ApiConfig.SETTING_MASTER_BASE_URL, _saved_master_setting)
	for i in REVERB_SETTINGS.size():
		ProjectSettings.set_setting(REVERB_SETTINGS[i], _saved_reverb_settings[i])
	for name in REVERB_ENVS:
		OS.unset_environment(name)


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


## 前提: API のベース URL が /api を含む。操作: api_origin。期待: スキーム + ホスト + ポートだけ
## （規約の HTML など public 配下の相対パスの前置きに使う）。
func test_api_origin_drops_path() -> void:
	assert_str(ApiConfig.api_origin()).is_equal("http://localhost:8090")
	ProjectSettings.set_setting(
		ApiConfig.SETTING_API_BASE_URL, "https://api.example.test:8443/api/"
	)
	assert_str(ApiConfig.api_origin()).is_equal("https://api.example.test:8443")


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


## 前提: Reverb の環境変数も設定も無い。操作: 各値と、接続先・認証先を読む。
## 期待: 既定値（旧 toast.gd の直書きだった nexus-local-key ではなく、ローカルのサーバーのアプリキー）と、
## API のベース URL の origin（:8090）に /broadcasting/auth を付けた認証 URL。
func test_reverb_defaults() -> void:
	assert_str(ApiConfig.reverb_host()).is_equal("localhost")
	assert_str(ApiConfig.reverb_port()).is_equal("8080")
	assert_str(ApiConfig.reverb_scheme()).is_equal("ws")
	assert_str(ApiConfig.reverb_app_key()).is_equal("nexus-local-key")
	assert_str(ApiConfig.reverb_ws_url()).is_equal("ws://localhost:8080/app/nexus-local-key")
	assert_str(ApiConfig.broadcasting_auth_url()).is_equal(
		"http://localhost:8090/broadcasting/auth"
	)


## 前提: [nexus] に Reverb の設定がある（ホストの末尾に / 付き）。期待: 既定値に勝ち、末尾の / は除かれる。
func test_reverb_project_setting_overrides_default() -> void:
	ProjectSettings.set_setting(ApiConfig.SETTING_REVERB_HOST, "reverb.test/")
	ProjectSettings.set_setting(ApiConfig.SETTING_REVERB_PORT, "6001")
	ProjectSettings.set_setting(ApiConfig.SETTING_REVERB_SCHEME, "wss")
	ProjectSettings.set_setting(ApiConfig.SETTING_REVERB_APP_KEY, "setting-key")
	assert_str(ApiConfig.reverb_ws_url()).is_equal("wss://reverb.test:6001/app/setting-key")


## 前提: 設定と環境変数の両方がある。期待: 環境変数が勝つ。
func test_reverb_environment_overrides_project_setting() -> void:
	ProjectSettings.set_setting(ApiConfig.SETTING_REVERB_HOST, "setting.test")
	ProjectSettings.set_setting(ApiConfig.SETTING_REVERB_APP_KEY, "setting-key")
	OS.set_environment(ApiConfig.ENV_REVERB_HOST, "env.test")
	OS.set_environment(ApiConfig.ENV_REVERB_PORT, "9999")
	OS.set_environment(ApiConfig.ENV_REVERB_APP_KEY, "env-key")
	assert_str(ApiConfig.reverb_ws_url()).is_equal("ws://env.test:9999/app/env-key")


## 前提: Reverb の環境変数が空文字。期待: 未設定として扱い、設定値（無ければ既定値）に進む。
func test_reverb_empty_environment_is_ignored() -> void:
	for name in REVERB_ENVS:
		OS.set_environment(name, "")
	ProjectSettings.set_setting(ApiConfig.SETTING_REVERB_PORT, "7000")
	assert_str(ApiConfig.reverb_host()).is_equal("localhost")
	assert_str(ApiConfig.reverb_port()).is_equal("7000")


## 前提: スキームが http / https / 大文字 / "://" 付きで書かれている（サーバーの REVERB_SCHEME と同じ書き方）。
## 期待: ws / wss に直る。未知の値は ws。
func test_reverb_scheme_is_normalized() -> void:
	var cases := {
		"http": "ws",
		"https": "wss",
		"WSS": "wss",
		"ws://": "ws",
		"https://": "wss",
		"unknown": "ws",
	}
	for input in cases:
		OS.set_environment(ApiConfig.ENV_REVERB_SCHEME, input)
		assert_str(ApiConfig.reverb_scheme()).is_equal(cases[input])


## 前提: API のベース URL を変える（パス付き・末尾 / 付き・ポート無し）。
## 期待: 認証 URL は origin に /broadcasting/auth を付けたもの（/api は含まない。Reverb のポートでもない）。
func test_broadcasting_auth_url_follows_api_base_url() -> void:
	OS.set_environment(ApiConfig.ENV_API_BASE_URL, "https://api.example.test/api/")
	assert_str(ApiConfig.broadcasting_auth_url()).is_equal(
		"https://api.example.test/broadcasting/auth"
	)
	OS.set_environment(ApiConfig.ENV_API_BASE_URL, "http://10.0.2.2:8090")
	assert_str(ApiConfig.broadcasting_auth_url()).is_equal("http://10.0.2.2:8090/broadcasting/auth")


## 前提: 既定の設定。操作: reverb_endpoint を作る。期待: ws_url と auth_url が上の各メソッドと同じ。
func test_reverb_endpoint_holds_both_urls() -> void:
	var endpoint := ApiConfig.reverb_endpoint()
	assert_str(endpoint.ws_url).is_equal(ApiConfig.reverb_ws_url())
	assert_str(endpoint.auth_url).is_equal(ApiConfig.broadcasting_auth_url())


# --- X-Platform（client_design.md 5-2） ---


## 前提: OS 名だけ。期待: iOS → Apple、Android → Google、それ以外（macOS・Windows・Linux・Web）→ Apple。
func test_platform_from_os_name() -> void:
	assert_str(ApiConfig.platform_from_os_name("iOS")).is_equal("Apple")
	assert_str(ApiConfig.platform_from_os_name("Android")).is_equal("Google")
	for os_name in ["macOS", "Windows", "Linux", "Web", ""]:
		assert_str(ApiConfig.platform_from_os_name(os_name)).is_equal("Apple")


## 前提: 環境変数・設定・OS 名の組み合わせ。期待: 環境変数 → 設定 → OS の既定の順。空文字は未設定。
func test_resolve_platform_priority() -> void:
	assert_str(ApiConfig.resolve_platform("", "", "Android")).is_equal("Google")
	assert_str(ApiConfig.resolve_platform("", "Google", "iOS")).is_equal("Google")
	assert_str(ApiConfig.resolve_platform("Apple", "Google", "Android")).is_equal("Apple")
	assert_str(ApiConfig.resolve_platform("  ", "Google", "iOS")).is_equal("Google")


## 前提: 大文字小文字・前後の空白が違う許可値。期待: 正規形（Apple / Google）に直る。
func test_resolve_platform_normalizes_case_and_whitespace() -> void:
	assert_str(ApiConfig.resolve_platform("google", "", "iOS")).is_equal("Google")
	assert_str(ApiConfig.resolve_platform(" APPLE ", "", "Android")).is_equal("Apple")


## 前提: 許可値でない上書き（iOS・Windows など）。期待: 警告を出して OS の既定に戻る
## （次の候補の設定値にも落ちない）。
func test_resolve_platform_invalid_override_falls_back_to_os_default() -> void:
	assert_str(ApiConfig.resolve_platform("iOS", "Google", "Android")).is_equal("Google")
	assert_str(ApiConfig.resolve_platform("iOS", "Google", "macOS")).is_equal("Apple")
	assert_str(ApiConfig.resolve_platform("", "Windows", "Android")).is_equal("Google")


## 前提: 環境変数と [nexus] の設定を実際に入れる。期待: platform() が環境変数 → 設定の順で読む。
func test_platform_reads_environment_then_project_setting() -> void:
	var saved: Variant = ProjectSettings.get_setting(ApiConfig.SETTING_PLATFORM, null)
	OS.unset_environment(ApiConfig.ENV_PLATFORM)
	ProjectSettings.set_setting(ApiConfig.SETTING_PLATFORM, "Google")
	assert_str(ApiConfig.platform()).is_equal("Google")
	OS.set_environment(ApiConfig.ENV_PLATFORM, "apple")
	assert_str(ApiConfig.platform()).is_equal("Apple")
	OS.unset_environment(ApiConfig.ENV_PLATFORM)
	ProjectSettings.set_setting(ApiConfig.SETTING_PLATFORM, saved)


## 前提: 環境変数 NEXUS_LANGUAGE を設定しても。期待: language() は常に "ja"（固定。上書きしない）。
func test_language_is_fixed_ja() -> void:
	OS.set_environment("NEXUS_LANGUAGE", "en")
	assert_str(ApiConfig.language()).is_equal("ja")
	OS.unset_environment("NEXUS_LANGUAGE")
