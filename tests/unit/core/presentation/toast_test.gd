## Toast の接続先・認証要求の組み立てのテスト。実際の WebSocket 接続・HTTP 送信はしない。
extends GdUnitTestSuite

const TOAST_SCRIPT := "res://core/presentation/toast.gd"

var _toast: Node


func before_test() -> void:
	# オートロードの Toast とは別の Node として作る（UI を組む _ready だけ走る。通信はしない）
	_toast = auto_free(load(TOAST_SCRIPT).new())
	add_child(_toast)


## 前提: connect_to_reverb 前の状態に、接続先・トークン・socket_id を直接入れる。操作: 認証要求を組み立てる。
## 期待: url は渡した endpoint の auth_url（直書きの localhost:8080 ではない）。ヘッダーに Bearer、
## 本文に socket_id とチャンネル名が入る。
func test_auth_request_uses_endpoint_auth_url() -> void:
	_toast._endpoint = ReverbEndpoint.new(
		"ws://reverb.test:6001/app/k", "http://api.test/broadcasting/auth"
	)
	_toast._access_token = "tok"
	_toast._socket_id = "123.456"
	var request: Dictionary = _toast._build_auth_request("private-notification.p1")
	assert_str(request["url"]).is_equal("http://api.test/broadcasting/auth")
	assert_array(Array(request["headers"])).contains(["Authorization: Bearer tok"])
	var body: Dictionary = JSON.parse_string(request["body"])
	assert_str(body["socket_id"]).is_equal("123.456")
	assert_str(body["channel_name"]).is_equal("private-notification.p1")


## 前提: endpoint が null。操作: connect_to_reverb。期待: 接続を始めず（WebSocket を作らず）、保持もしない。
func test_connect_without_endpoint_does_nothing() -> void:
	_toast.connect_to_reverb("p1", "tok", null)
	assert_object(_toast._ws).is_null()
	assert_str(_toast._user_id).is_equal("")
