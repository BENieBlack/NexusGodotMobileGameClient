## MasterDataApiRepository の単体テスト（version API の呼び出しと url の解決）。
## ApiClient は FakeApiClient（実通信なし）。
extends GdUnitTestSuite

var _client: FakeApiClient
var _repository: MasterDataApiRepository


func before_test() -> void:
	_client = auto_free(FakeApiClient.new())
	_repository = MasterDataApiRepository.new(_client)


## 前提: サーバーが 200 で needs_update: true を返す。操作: fetch_version(7)。
## 期待: GET /auth/version?deploy_version=7 を認証なしで送り、MasterVersion を返す。
## version は認証前に呼ぶので、Authorization を付けないこと（設計 5 節の確認の時機）を守る。
func test_fetch_version_success() -> void:
	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(
			200, {"needs_update": true, "sys_deploy_id": 8, "master": {"hash": "h", "tables": {}}}
		)
	var result := await _repository.fetch_version(7)
	assert_bool(result.ok).is_true()
	assert_int(result.version.sys_deploy_id).is_equal(8)
	assert_str(_client.calls[0]["method"]).is_equal("GET")
	assert_str(_client.calls[0]["url"]).ends_with("/auth/version?deploy_version=7")
	var headers: PackedStringArray = _client.calls[0]["headers"]
	assert_str(FakeApiClient.header_value(headers, "Authorization")).is_empty()


## 前提: サーバーが 299（デプロイ無し）/ 通信断。操作: fetch_version。
## 期待: 失敗で、AppError の kind は BUSINESS / NETWORK。
func test_fetch_version_failure_is_mapped_to_app_error() -> void:
	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(
			299, {"error_code": 99999, "message": "No active deploy data found"}
		)
	var business := await _repository.fetch_version(0)
	assert_bool(business.ok).is_false()
	assert_int(business.error.kind).is_equal(AppError.Kind.BUSINESS)
	assert_int(business.error.error_code).is_equal(99999)

	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.network_error()
	var network := await _repository.fetch_version(0)
	assert_int(network.error.kind).is_equal(AppError.Kind.NETWORK)


## 前提: url が相対 / 絶対 / 不正。操作: resolve_url。
## 期待: "/" 始まりは配信ホストを前置、http 始まりはそのまま、それ以外は空（失敗）。
func test_resolve_url() -> void:
	assert_str(MasterDataApiRepository.resolve_url("/masterdata/h/f.sqlite")).is_equal(
		ApiConfig.master_base_url() + "/masterdata/h/f.sqlite"
	)
	assert_str(MasterDataApiRepository.resolve_url("https://cdn.test/f")).is_equal(
		"https://cdn.test/f"
	)
	assert_str(MasterDataApiRepository.resolve_url("f.sqlite")).is_empty()
	assert_str(MasterDataApiRepository.resolve_url("")).is_empty()


## 前提: 配信ホストがバイト列を返す / 不正な url。操作: download_table。
## 期待: 成功ならバイト列、不正な url は通信せずに失敗（PARSE）。
func test_download_table() -> void:
	_client.handler = func(_m, _u, _h, _b):
		return {
			"result": HTTPRequest.RESULT_SUCCESS,
			"status": 200,
			"headers": PackedStringArray(),
			"body": PackedByteArray([9, 8]),
		}
	var ok := await _repository.download_table(
		MasterTable.new("mst_unit", "h", "/masterdata/h/f.sqlite", 2)
	)
	assert_bool(ok.ok).is_true()
	assert_array(ok.bytes).contains_exactly([9, 8])

	_client.calls.clear()
	var bad := await _repository.download_table(MasterTable.new("mst_unit", "h", "nope", 2))
	assert_bool(bad.ok).is_false()
	assert_int(_client.calls.size()).is_equal(0)
