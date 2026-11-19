## 新構成（AppContext・auth / login / player / agreement）だけで、実サーバーに対して
## sign_up → login → agreement → 再起動して sign_in → login が通るかを確かめる検証用スクリプト。
##
## 目的: 単体テストは通信を差し替えているので、署名ヘッダー・冪等キー・応答の取り込みが実サーバーと
##       結線できていることを第 2 段で 1 回確認する。製品コードではない（debug/ はエクスポート除外）。
## 使い方:
##   godot --headless --path . -s res://debug/verify_auth_login.gd
##   向き先: 環境変数 NEXUS_API_BASE_URL（ApiConfig の優先順。既定 http://localhost:8090/api）
## 流れ（保存先は user://verify_auth/。毎回消して新しい端末として始める）:
##   A. sign_up → login → POST /agreement/pending →（あれば）consent → もう一度 pending
##      → 存在しない規約への consent（24001 → pending の取り直し）
##      規約をシードしたサーバーで consent の正常系を確かめるときは、成功応答の本文が `[]`
##      （空の配列）でも ApiClient が成功扱いにすること（A4 が OK になること）を見る
##   B. 別の AppContext を作り直し（アプリの再起動）→ 保存トークンがあるので sign_in → login
##   C. トークンを消して authenticate → sign_up が 10004 → sign_in に切り替わる
##   D. 未登録の device_id + 保存トークンありで authenticate → sign_in が 10002 → sign_up に切り替わる
## 出力: 各段階の成否・AppError の kind / error_code・取り込めた項目数だけ。トークン・秘密鍵・device_id は出さない。
## 注意: サーバーのレート制限（sign_up は IP あたり 10 回/時間。このスクリプトは 3 回使う）。
## 終了コード: すべて期待どおりなら 0、1 つでも外れたら 1。
extends SceneTree

const WORK_DIR := "user://verify_auth/"
const APP_CONTEXT_PATH := "res://app/app_context.gd"

var _failed: bool = false


func _initialize() -> void:
	# _initialize の時点では root がまだ使えず HTTPRequest が失敗するので、1 フレーム待つ
	await process_frame
	print("API: ", ApiConfig.api_base_url())
	_remove_dir(WORK_DIR)

	# --- A. sign_up → login → agreement ---
	var ctx := _new_context()
	_check("A1 sign_up (新規)", await _authenticate(ctx))
	await _login_and_report(ctx, "A2")
	await _agreement_flow(ctx)

	# --- B. 再起動して sign_in ---
	ctx = await _restart(ctx)
	_check("B1 sign_in (保存トークンあり)", await _authenticate(ctx))
	await _login_and_report(ctx, "B2")

	# --- C. トークンなし + 登録済み device → sign_up が 10004 → sign_in ---
	ctx.clear_auth_session_use_case().handle()
	_check("C1 sign_up→10004→sign_in", await _authenticate(ctx))
	await _login_and_report(ctx, "C2")

	# --- D. 保存トークンあり + 未登録の device → sign_in が 10002 → sign_up ---
	ctx = await _restart(ctx)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WORK_DIR + "device_id.save"))
	_check("D1 sign_in→10002→sign_up", await _authenticate(ctx))

	ctx.queue_free()
	await process_frame
	quit(1 if _failed else 0)


## AuthenticateUseCase を、sign_up / sign_in の呼び出しを 1 行ずつ出す Repository で組み直して実行する
## （切り替えの途中の 299 を見るため。AppContext の中の Repository は触らない）。
func _authenticate(ctx: Node) -> Result:
	var logging := LoggingAuthRepository.new(
		AuthApiRepository.new(ctx.api_client(), ctx._auth_token_repository)
	)
	return await AuthenticateUseCase.new(logging, ctx._auth_token_repository).handle()


## 呼び出しの記録だけを足す AuthRepository。成功は HTTP 200、BUSINESS は HTTP 299 に対応する。
class LoggingAuthRepository:
	extends AuthRepository
	var _inner: AuthRepository

	func _init(inner: AuthRepository) -> void:
		_inner = inner

	func sign_up() -> AuthSessionResult:
		return _log("POST /auth/sign_up", await _inner.sign_up())

	func sign_in() -> AuthSessionResult:
		return _log("POST /auth/sign_in", await _inner.sign_in())

	func _log(label: String, result: AuthSessionResult) -> AuthSessionResult:
		if result.ok:
			print("    ", label, " -> HTTP 200 (トークン取得)")
		else:
			var error := result.error
			print(
				(
					"    %s -> kind=%s error_code=%d"
					% [label, AppError.Kind.keys()[error.kind], error.error_code]
				)
			)
		return result


func _new_context() -> Node:
	var ctx: Node = load(APP_CONTEXT_PATH).new()
	ctx.storage_root = WORK_DIR
	root.add_child(ctx)
	return ctx


## 今の AppContext を外し、同じ保存先で作り直す（アプリの再起動に相当）。
## 通信の後始末の途中で解放するとシグナル送出中の解放エラーになるので、queue_free して 1 フレーム待つ。
func _restart(old: Node) -> Node:
	root.remove_child(old)
	old.queue_free()
	await process_frame
	return _new_context()


func _login_and_report(ctx: Node, label: String) -> void:
	var key := IdempotencyKey.generate()
	var result: Result = await ctx.login_use_case().handle(key)
	_check(label + " login", result)
	if result.ok:
		var player: PlayerState = ctx._player_repository.current()
		var bonuses: Array[LoginBonus] = ctx._login_bonus_repository.list()
		var counts: Array = []
		for list_key in PlayerState.TRX_LIST_KEYS:
			counts.append(
				"%s=%d" % [list_key.trim_suffix("_list"), player.trx_list(list_key).size()]
			)
		print(
			(
				"    取り込み: sys_player=%d項目 %s login_bonus=%d件 user_id有=%s"
				% [
					player.sys_player.size(),
					" ".join(counts),
					bonuses.size(),
					player.user_id() != ""
				]
			)
		)
		for bonus in bonuses:
			print("    bonus: type=%s id=%s amount=%d" % [bonus.type, bonus.id, bonus.amount])


func _agreement_flow(ctx: Node) -> void:
	var pending: PendingAgreementsResult = await ctx.fetch_pending_agreements_use_case().handle()
	_check("A3 agreement/pending", pending)
	if not pending.ok:
		return
	print("    未同意の規約: %d件" % pending.agreements.size())
	for agreement in pending.agreements:
		var consent: ConsentAgreementResult = await ctx.consent_agreement_use_case().handle(
			agreement.sys_agreement_id, IdempotencyKey.generate()
		)
		_check("A4 consent id=%d" % agreement.sys_agreement_id, consent)
	if not pending.agreements.is_empty():
		var again: PendingAgreementsResult = await ctx.fetch_pending_agreements_use_case().handle()
		_check("A5 pending 再取得", again)
		print("    同意後の未同意: %d件" % again.agreements.size())
	# 存在しない規約への同意は 24001。UseCase が画面に出さず、未同意の一覧を取り直して返す
	var bogus: ConsentAgreementResult = await ctx.consent_agreement_use_case().handle(
		999999, IdempotencyKey.generate()
	)
	_check("A6 consent 存在しない規約(24001→取り直し)", bogus)
	print("    refetched=%s 取り直した件数=%d" % [bogus.refetched, bogus.agreements.size()])


## 結果を 1 行で出す。失敗は kind と error_code（本文・トークンは出さない）。
func _check(label: String, result: Result) -> void:
	if result.ok:
		print("OK   ", label)
		return
	_failed = true
	var error := result.error
	print(
		(
			"NG   %s kind=%s error_code=%d"
			% [label, AppError.Kind.keys()[error.kind], error.error_code]
		)
	)


func _remove_dir(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for file_name in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file_name))
	for dir_name in DirAccess.get_directories_at(absolute):
		_remove_dir(path + dir_name + "/")
	DirAccess.remove_absolute(absolute)
