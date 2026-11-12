## AppContext（合成ルート）の単体テスト（client_design.md 2-1、architecture.md 5 節 8）。
##
## AppContext は class_name を持たない（オートロード用）ので、load したスクリプトを Node として生成する。
## 保存先（storage_root）はテスト専用ディレクトリに向け、実機の user:// のトークン・マスターを使わない。
## 確かめること: 依存が組み立つこと、ApiClient のシグナルが EventBus に中継されること、
## session_expired の受け手が auth / player / login を空にし master_data の状態は残すこと、
## master_update_required で同期が裏で呼ばれること。
extends GdUnitTestSuite

const WORK_DIR := "user://test_app_context/"
const APP_CONTEXT_PATH := "res://app/app_context.gd"

var _context: Node


func before_test() -> void:
	_remove_dir(WORK_DIR)
	_context = _new_context()


func after_test() -> void:
	_remove_dir(WORK_DIR)


func _new_context() -> Node:
	var context: Node = auto_free(load(APP_CONTEXT_PATH).new())
	context.storage_root = WORK_DIR
	add_child(context)
	return context


## 前提: AppContext を add_child（_ready が走る）。操作: 取得メソッドを呼ぶ。
## 期待: ApiClient が子として 1 つ作られ、全 UseCase と mst の Repository が取得できる。
func test_builds_dependencies() -> void:
	assert_object(_context.api_client()).is_not_null()
	assert_object(_context.api_client().get_parent()).is_same(_context)
	assert_object(_context.check_master_data_use_case()).is_not_null()
	assert_object(_context.authenticate_use_case()).is_not_null()
	assert_object(_context.clear_auth_session_use_case()).is_not_null()
	assert_object(_context.apply_login_data_use_case()).is_not_null()
	assert_object(_context.login_use_case()).is_not_null()
	assert_object(_context.fetch_pending_agreements_use_case()).is_not_null()
	assert_object(_context.consent_agreement_use_case()).is_not_null()
	assert_object(_context.master_unit_repository()).is_not_null()
	assert_object(_context.master_equipment_repository()).is_not_null()
	assert_object(_context.master_gacha_repository()).is_not_null()


## 前提: ApiClient のトークン供給元に、保存済みのトークンがある（再起動の再現）。
## 期待: 同じ保存先で作り直した AppContext が、そのトークンで認証付きリクエストを組み立てられる
## （トークンの持ち主が LocalAuthTokenRepository 1 つで、ApiClient に渡っている）。
func test_token_store_is_shared_with_api_client() -> void:
	_context._auth_token_repository.save_tokens("acc", "ref")
	var restarted := _new_context()
	assert_str(restarted._auth_token_repository.access_token()).is_equal("acc")
	# ApiClient が参照する供給元は、AppContext の持つ Repository と同じ（_build が同じ 1 つを configure に渡す）
	assert_object(restarted.api_client()._auth_provider).is_same(restarted._auth_token_repository)
	assert_object(restarted.api_client()._master_hash_provider).is_same(restarted._master_storage)


## 前提: ApiClient が session_expired を出す。期待: EventBus.session_expired に中継される
## （core/data はオートロード名を参照できないので、app が載せ替える）。
func test_relays_session_expired_to_event_bus() -> void:
	var received := [0]
	var callback := func() -> void: received[0] += 1
	EventBus.session_expired.connect(callback)
	_context.api_client().session_expired.emit()
	EventBus.session_expired.disconnect(callback)
	assert_int(received[0]).is_equal(1)


## 前提: トークン・プレイヤー・ログインボーナスを持ち、device_id も作成済み。
## 操作: ApiClient が session_expired を出す。
## 期待: トークン・所持データ・ログインボーナスが全部空になる。device_id は残る
## （別の端末として sign_up され、同じ利用者に戻れなくなるのを防ぐ）。
func test_session_expired_clears_auth_player_and_login_bonus() -> void:
	_context._auth_token_repository.save_tokens("acc", "ref")
	var device_id: String = _context._auth_token_repository.device_id()
	_context.apply_login_data_use_case().handle({"my_id": "abc"}, {"trx_unit_list": [{"x": 1}]})
	var bonuses: Array[LoginBonus] = [LoginBonus.new("u", "gold", "gold", 1)]
	_context._login_bonus_repository.replace(bonuses)

	_context.api_client().session_expired.emit()

	assert_str(_context._auth_token_repository.access_token()).is_empty()
	assert_str(_context._auth_token_repository.refresh_token()).is_empty()
	assert_bool(_context._player_repository.current().is_empty()).is_true()
	assert_array(_context._login_bonus_repository.list()).is_empty()
	assert_str(_context._auth_token_repository.device_id()).is_equal(device_id)
	# 保存側も空（再起動しても未ログイン）
	assert_str(_new_context()._auth_token_repository.refresh_token()).is_empty()


## 前提: マスターの deploy_id を持つ端末（保存の状態を直接書く）。操作: session_expired。
## 期待: master_data の状態は消えない（マスターは端末のもので、アカウントに依存しない）。
func test_session_expired_keeps_master_state() -> void:
	var state := {"deploy_id": 9, "master_hash": "mh", "table_hashes": {}}
	var file := FileAccess.open(WORK_DIR + "master_state.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(state))
	file.close()
	var restarted := _new_context()
	assert_int(restarted._master_storage.deploy_id()).is_equal(9)

	restarted.api_client().session_expired.emit()

	assert_int(restarted._master_storage.deploy_id()).is_equal(9)
	assert_str(restarted._master_storage.master_hash()).is_equal("mh")


## 前提: master_data の同期 UseCase を、呼ばれた回数を数える物に差し替える。
## 操作: ApiClient が master_update_required を出す。
## 期待: EventBus に中継され、master_data の受け手が同期を 1 回呼ぶ。session_expired では呼ばれない。
func test_master_update_required_triggers_sync_in_background() -> void:
	var spy := SpyCheckMasterData.new()
	_context._check_master_data_use_case = spy

	_context.api_client().session_expired.emit()
	assert_int(spy.calls).is_equal(0)

	_context.api_client().master_update_required.emit()
	assert_int(spy.calls).is_equal(1)


## 前提: AppContext を解放する。操作: 解放後に EventBus へ emit。
## 期待: エラーにならない（EventBus はオートロードで長生きするので、受け手の登録を外してある）。
func test_event_bus_has_no_dangling_receivers_after_free() -> void:
	var context := _new_context()
	context.free()
	EventBus.session_expired.emit()
	EventBus.master_update_required.emit()
	assert_bool(true).is_true()


## 同期 UseCase の代わり。呼ばれた回数だけ数え、通信しない。
class SpyCheckMasterData:
	extends CheckMasterDataUseCase
	var calls: int = 0

	func _init() -> void:
		super(null, null)

	func handle() -> CheckMasterDataResult:
		calls += 1
		return CheckMasterDataResult.new(CheckMasterDataResult.Status.UP_TO_DATE)


func _remove_dir(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for file_name in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file_name))
	for dir_name in DirAccess.get_directories_at(absolute):
		_remove_dir(path + dir_name + "/")
	DirAccess.remove_absolute(absolute)
