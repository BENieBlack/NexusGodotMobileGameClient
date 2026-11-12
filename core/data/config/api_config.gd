## API のベース URL とマスター配信ホストを 1 か所で返す（client_design.md 2-4、ADR 0001）。
##
## 目的: 接続先を 3 か所に散らさない。向き先は検証時に変えたい（実サーバー・別ポート・障害の再現）ので、
##       コードを書き換えずに環境変数で上書きできるようにする。
## 値の決め方（上が優先）:
##   1. 環境変数 NEXUS_API_BASE_URL / NEXUS_MASTER_BASE_URL
##   2. project.godot の [nexus] セクション（api_base_url / master_base_url）
##   3. 既定値（DEFAULT_*。ローカルのサーバー: API :8090、配信 :8091）
## 返す値は末尾の "/" を除く（呼び出し側が "/auth/..." を連結するため、二重スラッシュを避ける）。
## リリースビルドでの切り替え方は別機能（client_design.md 8 節 4。仮置き）。
class_name ApiConfig
extends RefCounted

const DEFAULT_API_BASE_URL := "http://localhost:8090/api"
const DEFAULT_MASTER_BASE_URL := "http://localhost:8091"

const ENV_API_BASE_URL := "NEXUS_API_BASE_URL"
const ENV_MASTER_BASE_URL := "NEXUS_MASTER_BASE_URL"
const SETTING_API_BASE_URL := "nexus/api_base_url"
const SETTING_MASTER_BASE_URL := "nexus/master_base_url"


## API のベース URL（例: http://localhost:8090/api）。
static func api_base_url() -> String:
	return _resolve(ENV_API_BASE_URL, SETTING_API_BASE_URL, DEFAULT_API_BASE_URL)


## マスターデータの配信ホスト（例: http://localhost:8091）。version の url が "/" 始まりのときに前置する。
static func master_base_url() -> String:
	return _resolve(ENV_MASTER_BASE_URL, SETTING_MASTER_BASE_URL, DEFAULT_MASTER_BASE_URL)


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
