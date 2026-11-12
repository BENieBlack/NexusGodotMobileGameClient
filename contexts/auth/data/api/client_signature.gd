## sign_up の署名ヘッダー（HMAC-SHA256）を作る（サーバー api.md 1 節・3 節）。
##
## 目的: サーバーが sign_up の送り主を「正規のクライアント」と確かめるための署名を作る。
## 署名の規則: HMAC-SHA256(key = CLIENT_SECRET, message = "{timestamp}:{nonce}:{body}") を 16 進小文字にしたもの。
##   - timestamp: UNIX 秒（サーバーは現在時刻との差 300 秒以内を許す）
##   - nonce: リクエストごとの使い捨ての乱数（サーバーは 600 秒以内の再利用を拒む。毎回作り直す）
##   - body: 送る JSON 本文の文字列そのもの。ApiClient が送る本文と 1 文字も違ってはならないので、
##           呼び出し側は ApiClient と同じ JSON.stringify(body) の結果を渡す
## ヘッダー: X-Client-Timestamp / X-Client-Nonce / X-Client-Signature。
##   ローカルのサーバーが署名検証をスキップする設定（CLIENT_SIGNATURE_SKIP_IN_LOCAL）でも、常に付けて送る。
## 秘密鍵: 旧 auth_service.gd の定数を踏襲した仮置きの値（client_design.md 2-1。CLIENT_SECRET の保護は別機能 Q4）。
##   ログや print に出さない。
class_name ClientSignature
extends RefCounted

## 署名の鍵（仮置き。本番の鍵の置き場所と難読化は別機能で決める）
const CLIENT_SECRET := "your-secret-key-change-in-production-12345"

## nonce の長さ（バイト）。16 バイト = 16 進で 32 文字（旧実装の 32 文字と同じ長さ）
const NONCE_BYTES := 16


## 署名ヘッダー 3 種を作る。timestamp と nonce は呼ばれるたびに作り直す。
## 引数 body は、送る JSON 本文の文字列。戻り値は "Name: value" の配列。
static func create_headers(body: String) -> PackedStringArray:
	var timestamp := str(int(Time.get_unix_time_from_system()))
	var nonce := Crypto.new().generate_random_bytes(NONCE_BYTES).hex_encode()
	return PackedStringArray(
		[
			"X-Client-Timestamp: " + timestamp,
			"X-Client-Nonce: " + nonce,
			"X-Client-Signature: " + compute_signature(timestamp, nonce, body),
		]
	)


## "{timestamp}:{nonce}:{body}" の HMAC-SHA256 を 16 進小文字で返す。secret は既定で CLIENT_SECRET
## （テストが既知の値で確かめられるよう引数にしてある）。
static func compute_signature(
	timestamp: String, nonce: String, body: String, secret: String = CLIENT_SECRET
) -> String:
	var message := "%s:%s:%s" % [timestamp, nonce, body]
	var digest := Crypto.new().hmac_digest(
		HashingContext.HASH_SHA256, secret.to_utf8_buffer(), message.to_utf8_buffer()
	)
	return digest.hex_encode()
