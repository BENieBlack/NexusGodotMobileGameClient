## API のベース URL とマスター配信ホストを 1 か所で返す（client_design.md 2-4、ADR 0001）。
##
## 目的: 接続先を 3 か所に散らさない。向き先は検証時に変えたい（実サーバー・別ポート・障害の再現）ので、
##       コードを書き換えずに環境変数で上書きできるようにする。
## 値の決め方（上が優先）:
##   1. 環境変数 NEXUS_API_BASE_URL / NEXUS_MASTER_BASE_URL
##   2. project.godot の [nexus] セクション（api_base_url / master_base_url）
##   3. 既定値（DEFAULT_*。ローカルのサーバー: API :8090、配信 :8091）
## Reverb（WebSocket の通知）の接続先も同じ順で決める（環境変数 NEXUS_REVERB_HOST / _PORT / _SCHEME / _APP_KEY、
## [nexus] の reverb_host / reverb_port / reverb_scheme / reverb_app_key、既定値 DEFAULT_REVERB_*）。
## チャンネル認証の URL（/broadcasting/auth）は Reverb のサーバーではなく API サーバーのルートにあるので、
## API のベース URL（api_base_url）の origin（スキーム + ホスト + ポート）から作る。
## X-Platform の値も同じ順で決める（NEXUS_PLATFORM、[nexus] の platform、OS の既定。platform()）。
## 返す値は末尾の "/" を除く（呼び出し側が "/auth/..." を連結するため、二重スラッシュを避ける）。
## リリースビルドでの切り替え方は別機能（client_design.md 8 節 4。仮置き）。
class_name ApiConfig
extends RefCounted

const DEFAULT_API_BASE_URL := "http://localhost:8090/api"
const DEFAULT_MASTER_BASE_URL := "http://localhost:8091"

const DEFAULT_REVERB_HOST := "localhost"
const DEFAULT_REVERB_PORT := "8080"
const DEFAULT_REVERB_SCHEME := "ws"
const DEFAULT_REVERB_APP_KEY := "nexus-local-key"
## チャンネル認証のパス（サーバーの Broadcast ルート。/api の下ではなく API サーバーのルート直下）
const BROADCASTING_AUTH_PATH := "/broadcasting/auth"

const ENV_API_BASE_URL := "NEXUS_API_BASE_URL"
const ENV_MASTER_BASE_URL := "NEXUS_MASTER_BASE_URL"
const ENV_REVERB_HOST := "NEXUS_REVERB_HOST"
const ENV_REVERB_PORT := "NEXUS_REVERB_PORT"
const ENV_REVERB_SCHEME := "NEXUS_REVERB_SCHEME"
const ENV_REVERB_APP_KEY := "NEXUS_REVERB_APP_KEY"
const ENV_PLATFORM := "NEXUS_PLATFORM"
const SETTING_API_BASE_URL := "nexus/api_base_url"
const SETTING_MASTER_BASE_URL := "nexus/master_base_url"
const SETTING_REVERB_HOST := "nexus/reverb_host"
const SETTING_REVERB_PORT := "nexus/reverb_port"
const SETTING_REVERB_SCHEME := "nexus/reverb_scheme"
const SETTING_REVERB_APP_KEY := "nexus/reverb_app_key"
const SETTING_PLATFORM := "nexus/platform"

## X-Platform ヘッダーの許可値（サーバー api.md 10 節。完全一致）
const PLATFORM_APPLE := "Apple"
const PLATFORM_GOOGLE := "Google"


## API のベース URL（例: http://localhost:8090/api）。
static func api_base_url() -> String:
	return _resolve(ENV_API_BASE_URL, SETTING_API_BASE_URL, DEFAULT_API_BASE_URL)


## マスターデータの配信ホスト（例: http://localhost:8091）。version の url が "/" 始まりのときに前置する。
static func master_base_url() -> String:
	return _resolve(ENV_MASTER_BASE_URL, SETTING_MASTER_BASE_URL, DEFAULT_MASTER_BASE_URL)


## Reverb のホスト（例: localhost）。
static func reverb_host() -> String:
	return _resolve(ENV_REVERB_HOST, SETTING_REVERB_HOST, DEFAULT_REVERB_HOST)


## Reverb のポート（例: 8080。文字列で返す）。
static func reverb_port() -> String:
	return _resolve(ENV_REVERB_PORT, SETTING_REVERB_PORT, DEFAULT_REVERB_PORT)


## Reverb のスキーム。"ws" か "wss"。サーバーの REVERB_SCHEME と同じ "http" / "https" や "://" 付きで
## 書かれても、ws / wss に直す（大文字小文字も区別しない）。
static func reverb_scheme() -> String:
	var scheme := _resolve(ENV_REVERB_SCHEME, SETTING_REVERB_SCHEME, DEFAULT_REVERB_SCHEME)
	scheme = scheme.to_lower().trim_suffix("://").trim_suffix(":")
	match scheme:
		"https", "wss":
			return "wss"
		_:
			return "ws"


## Reverb のアプリキー（接続先のパス /app/<キー> に入る）。
static func reverb_app_key() -> String:
	return _resolve(ENV_REVERB_APP_KEY, SETTING_REVERB_APP_KEY, DEFAULT_REVERB_APP_KEY)


## WebSocket の接続先（例: ws://localhost:8080/app/nexus-local-key）。
static func reverb_ws_url() -> String:
	return "%s://%s:%s/app/%s" % [reverb_scheme(), reverb_host(), reverb_port(), reverb_app_key()]


## チャンネル認証の URL（例: http://localhost:8090/broadcasting/auth）。
## API のベース URL の origin に BROADCASTING_AUTH_PATH を付ける（ベース URL の /api は含めない）。
static func broadcasting_auth_url() -> String:
	return _origin_of(api_base_url()) + BROADCASTING_AUTH_PATH


## API の origin（スキーム + ホスト + ポート。例: http://localhost:8090）。
## サーバーの public 配下の静的ファイル（規約の HTML など）は /api の外にあるため、その相対パスの前置きに使う。
static func api_origin() -> String:
	return _origin_of(api_base_url())


## Toast へ渡す、Reverb の接続先と認証先の入れ物を作る。
static func reverb_endpoint() -> ReverbEndpoint:
	return ReverbEndpoint.new(reverb_ws_url(), broadcasting_auth_url())


## X-Platform ヘッダーの値（"Apple" か "Google"）。client_design.md 5-2。
## 優先順: 環境変数 NEXUS_PLATFORM → [nexus] の platform → OS の既定。
## 上書きの値が不正なときは警告を出して OS の既定に戻す（誤った値で全 API が 99003 になるのを避ける）。
static func platform() -> String:
	return resolve_platform(
		OS.get_environment(ENV_PLATFORM),
		str(ProjectSettings.get_setting(SETTING_PLATFORM, "")),
		OS.get_name()
	)


## platform() の決定ロジック（純粋関数。環境変数・設定・OS 名を引数で受けるのでテストしやすい）。
## 空文字は「未設定」とみなして次の候補へ進む。値は前後の空白を除き、大文字小文字を区別せず
## 正規形（Apple / Google）に直す。それ以外は警告して OS の既定を返す。
static func resolve_platform(env_value: String, setting_value: String, os_name: String) -> String:
	for override_value in [env_value, setting_value]:
		var trimmed: String = override_value.strip_edges()
		if trimmed == "":
			continue
		var normalized := _normalize_platform(trimmed)
		if normalized != "":
			return normalized
		push_warning("X-Platform の設定値が不正です（%s）。Apple / Google のどちらかを指定してください。OS の既定に戻します" % trimmed)
		return platform_from_os_name(os_name)
	return platform_from_os_name(os_name)


## OS 名（OS.get_name()）から既定の platform を決める。iOS → Apple、Android → Google、
## それ以外（macOS・Windows・Linux・Web・エディタ）は Apple（サーバーの付与の既定・開発シードに揃える）。
static func platform_from_os_name(os_name: String) -> String:
	if os_name == "Android":
		return PLATFORM_GOOGLE
	return PLATFORM_APPLE


## 許可値なら正規形を、そうでなければ空文字を返す（大文字小文字を区別しない）。
static func _normalize_platform(value: String) -> String:
	match value.to_lower():
		"apple":
			return PLATFORM_APPLE
		"google":
			return PLATFORM_GOOGLE
		_:
			return ""


## URL の origin（スキーム + ホスト + ポート）を返す。"://" が無い値はそのまま（末尾の / は除く）返す。
static func _origin_of(url: String) -> String:
	var scheme_end := url.find("://")
	if scheme_end < 0:
		return url.rstrip("/")
	var path_start := url.find("/", scheme_end + 3)
	if path_start < 0:
		return url
	return url.substr(0, path_start)


## 環境変数 → ProjectSettings → 既定値の順で最初に見つかった値を返す。
## 空文字は「未設定」とみなして次へ進む（環境変数を空で渡されたときに接続先が空にならないように）。
static func _resolve(env_name: String, setting_name: String, default_value: String) -> String:
	var env_value := OS.get_environment(env_name)
	if env_value != "":
		return env_value.rstrip("/")
	var setting_value := str(ProjectSettings.get_setting(setting_name, ""))
	if setting_value != "":
		return setting_value.rstrip("/")
	return default_value.rstrip("/")
