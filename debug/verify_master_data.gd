## 新しい ApiClient + master_data が実サーバーの GET /auth/version に通じるかを確かめる検証用スクリプト。
##
## 目的: 単体テストは通信を差し替えているので、実サーバーとの結線（URL・ヘッダー・分類・応答の取り込み）が
##       本当に通じることを、第 1 段（core と master_data）の段階で 1 回確認する。製品コードではない。
## 使い方:
##   godot --headless --path . -s res://debug/verify_master_data.gd
##   向き先を変えるとき: 環境変数 NEXUS_API_BASE_URL と NEXUS_MASTER_BASE_URL を付ける（ApiConfig の優先順）
## 流れ:
##   1. ApiClient を作って SceneTree に足し、master_data の Repository と UseCase を組み立てる
##      （保存先は user://verify_master/ にして、実際の user://master を汚さない）
##   2. version API だけを呼び、結果（成功 / AppError の種別）を表示する
##   3. CheckMasterDataUseCase.handle() を実行し、status を表示する
## 終了コード: version が成功（needs_update の真偽を問わない）なら 0。失敗（通信不可・業務エラーなど）なら 1。
##   サーバーに有効なデプロイが無い（シード前）と業務エラー 99999 を返す。これは通信路としては正常なので、
##   種別が BUSINESS のときは「サーバーには届いた」と表示する（終了コードは 1 のまま）。
extends SceneTree

const WORK_DIR := "user://verify_master/"


func _initialize() -> void:
	# --- 1. 組み立て ---
	# _initialize の時点ではまだ root がツリーに入っておらず、HTTPRequest.request() が
	# ERR_UNCONFIGURED で失敗する（NETWORK に見える）。1 フレーム待ってから始める
	await process_frame
	var api_client := ApiClient.new()
	root.add_child(api_client)
	var database := MasterDatabase.new()
	var storage := LocalMasterDataRepository.new(
		database, WORK_DIR + "master/", WORK_DIR + "state.json"
	)
	storage.initialize()
	api_client.configure(null, storage)
	var remote := MasterDataApiRepository.new(api_client)
	print("API: ", ApiConfig.api_base_url(), "  配信: ", ApiConfig.master_base_url())

	# --- 2. version API を直接呼ぶ ---
	var version_result := await remote.fetch_version(storage.deploy_id())
	var exit_code := 0
	if version_result.ok:
		var version := version_result.version
		print(
			(
				"version OK: needs_update=%s sys_deploy_id=%d tables=%d"
				% [version.needs_update, version.sys_deploy_id, version.tables.size()]
			)
		)
	else:
		exit_code = 1
		var error := version_result.error
		print(
			(
				"version 失敗: kind=%s error_code=%d message=%s"
				% [AppError.Kind.keys()[error.kind], error.error_code, error.message]
			)
		)
		if error.kind == AppError.Kind.BUSINESS:
			print("  （サーバーには届いている。有効な sys_deploy が無い状態）")

	# --- 3. 同期 UseCase を通す ---
	var use_case := CheckMasterDataUseCase.new(remote, storage)
	use_case.download_progress.connect(
		func(current: int, total: int, name: String) -> void:
			print("  更新中 (%d/%d) %s" % [current, total, name])
	)
	var result := await use_case.handle()
	print(
		(
			"CheckMasterDataUseCase: status=%s ok=%s message=%s"
			% [CheckMasterDataResult.Status.keys()[result.status], result.ok, result.message]
		)
	)

	database.close_all()
	api_client.queue_free()
	quit(exit_code)
