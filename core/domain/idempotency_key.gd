## 冪等キー（X-Unique-Request-Identifier）の作成と再利用の規則（client_design.md 3-4、D6）。
##
## 目的: 変更を伴う認証付き POST（login・consent）の二重送信を、サーバーの冪等チェックで
##       1 回の処理にまとめる。キーの寿命は「ひとつの操作」で、持つのは呼び出し元（presenter）。
## 使い方:
##   1. 操作の開始時に generate() でキーを作って保持する
##   2. 失敗して再送するとき can_reuse(error.kind) が true なら同じキーで送る。false なら作り直す
##   3. 成功したら捨てる（次の操作では新しいキー）
## 規則の根拠: サーバーが結果を保存するのは 2xx と業務エラー（HTTP 299）だけ。
##   - 299 は「同じエラーが返り続ける」ので、作り直さないと直せない
##   - それ以外の失敗（通信断・409・503・500・401 など）は保存されない、または未処理の
##     可能性があるので、再利用する（処理済みだった場合は保存済みの結果が返る）
class_name IdempotencyKey
extends RefCounted


## UUID v4 のキーを作る。
## Crypto の乱数を使う（randi() は暗号論的でなく、衝突・予測を避けたい）。
static func generate() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	# UUID v4 の規約: 7 バイト目の上位 4 bit = 4（版）、9 バイト目の上位 2 bit = 10（variant）
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	var uuid := ""
	for i in range(16):
		# 8-4-4-4-12 の区切り（バイト位置 4・6・8・10 の手前）
		if i == 4 or i == 6 or i == 8 or i == 10:
			uuid += "-"
		uuid += "%02x" % bytes[i]
	return uuid


## 直前の失敗のあとで、同じキーのまま再送してよいか。
## 業務エラー（BUSINESS）だけ false（保存済みなので、作り直さないと同じエラーが返る）。
## 成功のあとの再利用はしない（呼び出し側が捨てる）ので、ここでは失敗の種別だけを見る。
static func can_reuse(kind: AppError.Kind) -> bool:
	return kind != AppError.Kind.BUSINESS
