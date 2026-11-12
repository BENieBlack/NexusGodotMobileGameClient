## AuthApiRepository の単体テスト。偽の通信（FakeApiClient）で、送る内容と応答の取り込みを確かめる。
extends GdUnitTestSuite

const WORK_DIR := "user://test_auth_api/"

var _client: FakeApiClient
var _tokens: LocalAuthTokenRepository
var _repository: AuthApiRepository


func before_test() -> void:
	_remove_dir()
	_client = auto_free(FakeApiClient.new())
	_tokens = LocalAuthTokenRepository.new(WORK_DIR)
	_repository = AuthApiRepository.new(_client, _tokens)


func after_test() -> void:
	_remove_dir()


func _success_body() -> Dictionary:
	return {
		"sys_player": {"my_id": "abcd1234", "name": "n"},
		"token": {"access_token": "acc", "refresh_token": "ref", "expires_in": 3600},
	}


## 前提: サーバーが 200 とトークンを返す。操作: sign_up。
## 期待: POST /auth/sign_up に device_id と device_info（4 項目）を送り、署名ヘッダー 3 種が付く。
## 署名は送った本文の文字列に対するもの（本文が 1 文字でも違えばサーバーが拒む）。
## Authorization は付かない（認証前）。冪等キーも付かない。トークンを取り込む。
func test_sign_up_sends_signed_request_and_parses_session() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, _success_body())
	var result := await _repository.sign_up()

	assert_bool(result.ok).is_true()
	assert_str(result.session.access_token).is_equal("acc")
	assert_str(result.session.refresh_token).is_equal("ref")

	var call: Dictionary = _client.calls[0]
	assert_str(call["method"]).is_equal("POST")
	assert_str(call["url"]).ends_with("/auth/sign_up")
	var sent: Dictionary = JSON.parse_string(call["body"])
	assert_str(sent["device_id"]).is_equal(_tokens.device_id())
	assert_array(sent["device_info"].keys()).contains_exactly_in_any_order(
		["os", "os_version", "model", "app_version"]
	)
	assert_str(str(sent["device_info"]["app_version"])).is_not_empty()
	var headers: PackedStringArray = call["headers"]
	var expected := ClientSignature.compute_signature(
		FakeApiClient.header_value(headers, "X-Client-Timestamp"),
		FakeApiClient.header_value(headers, "X-Client-Nonce"),
		call["body"]
	)
	assert_str(FakeApiClient.header_value(headers, "X-Client-Signature")).is_equal(expected)
	assert_str(FakeApiClient.header_value(headers, "Authorization")).is_empty()
	assert_str(FakeApiClient.header_value(headers, "X-Unique-Request-Identifier")).is_empty()


## 前提: サーバーが 200 を返す。操作: sign_in。
## 期待: POST /auth/sign_in に device_id と device_info を送る（sign_in は device_info 必須）。
## 署名ヘッダーは付けない（sign_up だけ）。
func test_sign_in_sends_device_info_without_signature() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, _success_body())
	var result := await _repository.sign_in()

	assert_bool(result.ok).is_true()
	var call: Dictionary = _client.calls[0]
	assert_str(call["url"]).ends_with("/auth/sign_in")
	var sent: Dictionary = JSON.parse_string(call["body"])
	assert_int(sent["device_info"].size()).is_equal(4)
	assert_str(FakeApiClient.header_value(call["headers"], "X-Client-Signature")).is_empty()


## 前提: 299 の 10004 / 通信失敗。操作: sign_up。
## 期待: AppError に直る（BUSINESS と error_code、NETWORK）。
func test_failures_become_app_errors() -> void:
	_client.handler = func(_m, _u, _h, _b):
		return FakeApiClient.response(299, {"error_code": 10004, "message": "m"})
	var business := await _repository.sign_up()
	assert_int(business.error.kind).is_equal(AppError.Kind.BUSINESS)
	assert_int(business.error.error_code).is_equal(10004)

	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.network_error()
	var network := await _repository.sign_up()
	assert_int(network.error.kind).is_equal(AppError.Kind.NETWORK)


## 前提: 200 だが token が欠落 / null。操作: sign_in。
## 期待: PARSE の失敗（空のトークンを保存して「未ログイン」に戻るのを防ぐ）。
func test_missing_token_is_parse_error() -> void:
	_client.handler = func(_m, _u, _h, _b): return FakeApiClient.response(200, {"token": null})
	var result := await _repository.sign_in()
	assert_bool(result.ok).is_false()
	assert_int(result.error.kind).is_equal(AppError.Kind.PARSE)


## 前提: 上限を超える長さの os / os_version / model。操作: build_device_info。
## 期待: サーバーの最大長（50 / 50 / 100）に切り詰め、空は "unknown"（超えると 422 になるのを防ぐ）。
func test_device_info_is_truncated_to_server_limits() -> void:
	var info := AuthApiRepository.build_device_info("a".repeat(80), "b".repeat(80), "c".repeat(150))
	assert_str(info["os"]).has_length(50)
	assert_str(info["os_version"]).has_length(50)
	assert_str(info["model"]).has_length(100)
	assert_int(str(info["app_version"]).length()).is_less_equal(20)
	assert_str(AuthApiRepository.build_device_info("", "", "")["model"]).is_equal("unknown")


func _remove_dir() -> void:
	var absolute := ProjectSettings.globalize_path(WORK_DIR)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for file_name in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file_name))
	DirAccess.remove_absolute(absolute)
