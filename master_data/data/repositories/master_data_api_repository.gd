## version API の呼び出しと、マスター配信ファイルのダウンロード（MasterDataRemoteRepository の実装）。
##
## 目的: ApiClient の結果（ApiResult）を、domain が扱う結果型（AppError つき）に直す。
## 流れ:
##   fetch_version: GET /auth/version?deploy_version=N（認証なし。X-Master-Hash は ApiClient が付ける）
##     → VersionResponse → MasterVersion。HTTP 200 以外・失敗は AppError で返す
##   download_table: version の url を絶対 URL にして ApiClient.download で取得する
## url の解決（client_design.md 2-4、ADR 0001）: "/" 始まりの相対パスは配信ホスト（ApiConfig）を前置し、
##   "http" 始まりの絶対 URL はそのまま使う（将来サーバーが基準 URL を返す案への互換）。それ以外は失敗。
class_name MasterDataApiRepository
extends MasterDataRemoteRepository

var _api_client: ApiClient


func _init(api_client: ApiClient) -> void:
	_api_client = api_client


## version API を呼ぶ。
func fetch_version(deploy_id: int) -> MasterVersionResult:
	var api_result := await _api_client.request(
		"GET", "/auth/version?deploy_version=%d" % deploy_id, {}, {"auth": false}
	)
	if not api_result.ok:
		return MasterVersionResult.new(null, api_result.to_app_error())
	# 200 以外の 2xx は想定外（サーバー api.md は 200）。成功扱いにせず失敗として返す
	if api_result.http_status != 200:
		var error := AppError.new(
			AppError.Kind.SERVER_ERROR, "version が HTTP %d でした" % api_result.http_status
		)
		return MasterVersionResult.new(null, error)
	return MasterVersionResult.new(VersionResponse.from_dict(api_result.data).to_domain())


## テーブル 1 つの SQLite ファイルを取得する。
func download_table(table: MasterTable) -> MasterTableFileResult:
	var url := resolve_url(table.url)
	if url == "":
		return MasterTableFileResult.new(
			PackedByteArray(), AppError.new(AppError.Kind.PARSE, "配信 URL が不正です")
		)
	var api_result := await _api_client.download(url)
	if not api_result.ok:
		return MasterTableFileResult.new(PackedByteArray(), api_result.to_app_error())
	return MasterTableFileResult.new(api_result.raw_body)


## version の url を絶対 URL にする。解決できなければ空文字。
static func resolve_url(url: String) -> String:
	if url.begins_with("http"):
		return url
	if url.begins_with("/"):
		return ApiConfig.master_base_url() + url
	return ""
