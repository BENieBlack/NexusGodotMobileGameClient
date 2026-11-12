## ErrorMessages の単体テスト（client_design.md 1-3 の表）: エラー種別ごとの表示文言と再試行の無効秒数。
##
## 種別ごとに文言が出し分けられること、メンテナンスはサーバーの title / message / end_at を使うこと、
## 429 だけ再試行ボタンを無効にする秒数が出ることを確かめる。
extends GdUnitTestSuite


func _error(kind: AppError.Kind) -> AppError:
	return AppError.new(kind)


## 前提: 通信失敗（NETWORK）。期待: 電波を案内する文言。
func test_network_text() -> void:
	assert_str(ErrorMessages.text(_error(AppError.Kind.NETWORK))).contains("電波の良い場所")


## 前提: メンテナンス（503）で title / message / end_at がある。期待: 3 つとも出る。
## 無ければ既定の文言（サーバーが本文を返さない場合でも空にならない）。
func test_maintenance_uses_server_fields_or_default() -> void:
	var error := _error(AppError.Kind.MAINTENANCE)
	error.maintenance = {"title": "定期メンテ", "message": "作業中です", "end_at": "2099-01-01 00:00:00"}
	var text := ErrorMessages.text(error)
	assert_str(text).contains("定期メンテ")
	assert_str(text).contains("作業中です")
	assert_str(text).contains("2099-01-01")

	var plain := _error(AppError.Kind.MAINTENANCE)
	assert_str(ErrorMessages.text(plain)).is_equal("ただいまメンテナンス中です")


## 前提: end_at が null（終了未定）。期待: 「終了予定」の行を出さない。
func test_maintenance_without_end_at_omits_schedule() -> void:
	var error := _error(AppError.Kind.MAINTENANCE)
	error.maintenance = {"title": "メンテ", "message": "", "end_at": null}
	assert_str(ErrorMessages.text(error)).is_equal("メンテ")


## 前提: 429 で retry_after がある / ない。期待: 秒数入りの固定文 / 秒数なしの文。
func test_rate_limited_text_with_and_without_retry_after() -> void:
	var limited := _error(AppError.Kind.RATE_LIMITED)
	limited.retry_after = 30
	assert_str(ErrorMessages.text(limited)).contains("あと約 30 秒後")
	assert_str(ErrorMessages.text(_error(AppError.Kind.RATE_LIMITED))).is_equal(
		"アクセスが集中しています。しばらくしてからお試しください"
	)


## 前提: 業務エラー（299）。期待: コード入りの文言（message は補助表示）。
func test_business_text_has_code() -> void:
	var error := _error(AppError.Kind.BUSINESS)
	error.error_code = 20001
	error.message = "補助"
	var text := ErrorMessages.text(error)
	assert_str(text).contains("コード: 20001")
	assert_str(text).contains("補助")


## 前提: 409・503（SERVER_BUSY）・セッション失効・422・パース失敗。期待: それぞれ設計 1-3 の文言。
func test_other_kinds() -> void:
	assert_str(ErrorMessages.text(_error(AppError.Kind.CONFLICT))).contains("処理中です")
	assert_str(ErrorMessages.text(_error(AppError.Kind.SERVER_BUSY))).is_equal("しばらくしてからお試しください")
	assert_str(ErrorMessages.text(_error(AppError.Kind.SESSION_EXPIRED))).contains("最初からやり直します")
	assert_str(ErrorMessages.text(_error(AppError.Kind.VALIDATION))).contains("422")
	assert_str(ErrorMessages.text(_error(AppError.Kind.PARSE))).contains("読めませんでした")


## 前提: 署名不正（sign_up の 401）で、時刻ずれ（REQUEST_EXPIRED）とそれ以外。
## 期待: 時刻ずれだけ「端末の時刻」を案内する（利用者が直せるため別文言）。
func test_signature_text_distinguishes_clock_skew() -> void:
	var skew := _error(AppError.Kind.SIGNATURE)
	skew.error_name = "REQUEST_EXPIRED"
	assert_str(ErrorMessages.text(skew)).contains("端末の時刻")
	assert_str(ErrorMessages.text(_error(AppError.Kind.SIGNATURE))).contains("端末の確認に失敗")


## 前提: サーバーエラー（error_code あり / なし）。期待: あればコードを添える。
func test_server_error_text() -> void:
	var with_code := _error(AppError.Kind.SERVER_ERROR)
	with_code.error_code = 500
	assert_str(ErrorMessages.text(with_code)).contains("コード: 500")
	assert_str(ErrorMessages.text(_error(AppError.Kind.SERVER_ERROR))).is_equal("サーバーでエラーが発生しました")


## 前提: 429（retry_after = 7）とそれ以外。期待: 429 だけ 7 秒、他は 0（すぐ押せる）。
func test_retry_lock_seconds_only_for_rate_limited() -> void:
	var limited := _error(AppError.Kind.RATE_LIMITED)
	limited.retry_after = 7
	assert_int(ErrorMessages.retry_lock_seconds(limited)).is_equal(7)
	assert_int(ErrorMessages.retry_lock_seconds(_error(AppError.Kind.NETWORK))).is_equal(0)
	assert_int(ErrorMessages.retry_lock_seconds(null)).is_equal(0)
