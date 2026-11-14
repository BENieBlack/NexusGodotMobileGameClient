## ホームの表示値（HomeSummary）を組み立てる UseCase（client_design.md 2-2・3-2・4・6）。
##
## 目的: 保持している PlayerState（login 応答）と、ローカルのマスター（mst_player_level・mst_config）から、
##       ホームが出す値を 1 回で作る。ホームを開いたときと master_data_loaded（マスター更新）のときに呼ぶ。
##       マスターはここで 1 回だけ読む（tick ごとに SQLite を引かない）。通信しない。
## 読めないときの扱い（1-3 の表）: 最大値が分からない → max_stamina = -1、回復間隔が分からない（無い・整数でない・
##       1 未満）→ interval_seconds = 0、起点が読めない → recovered_at_unix = -1・rate_x100 = 0。
##       どれも例外にせず、StaminaRecovery が「回復を計算しない」側に倒す。
class_name GetHomeSummaryUseCase
extends RefCounted

var _player_repository: PlayerRepository
var _mst_player_level_repository: MstPlayerLevelRepository
var _mst_config_repository: MstConfigRepository


func _init(
	player_repository: PlayerRepository,
	mst_player_level_repository: MstPlayerLevelRepository,
	mst_config_repository: MstConfigRepository
) -> void:
	_player_repository = player_repository
	_mst_player_level_repository = mst_player_level_repository
	_mst_config_repository = mst_config_repository


func handle() -> HomeSummary:
	var state := _player_repository.current()
	var summary := HomeSummary.new()
	# 未ログイン（状態が空）は既定値のまま返す。画面が「ログインしていません」と「-」を出す
	if state.is_empty():
		return summary
	summary.is_logged_in = true
	summary.player_id = state.user_id()
	# name が null のとき str(null) は "<null>" になるので、String のときだけ採用する（6 節）
	var raw_name: Variant = state.sys_player.get("name", null)
	summary.player_name = raw_name if raw_name is String else ""
	var level := -1
	var raw_level: Variant = state.sys_player.get("level", null)
	if raw_level is int or raw_level is float:
		level = int(raw_level)
	summary.level = level
	summary.coin = CoinAmount.calculate(state.trx_list("trx_wallet_list"))
	summary.diamond_total = DiamondTotal.calculate(
		state.trx_diamond, state.trx_list("trx_item_list")
	)
	summary.stamina_source = _build_stamina_source(state, level)
	return summary


## スタミナの起点を作る。type が normal で、削除されていない最初の行を使う（P1）。無ければ is_present = false。
func _build_stamina_source(state: PlayerState, level: int) -> StaminaSource:
	var source := StaminaSource.new()
	source.max_stamina = _max_stamina(level)
	source.interval_seconds = _interval_seconds()
	for row in state.trx_list("trx_stamina_list"):
		if not row is Dictionary:
			continue
		if str(row.get("type", "")) != PlayerResourceIds.STAMINA_TYPE_NORMAL:
			continue
		if PlayerState.is_row_deleted(row):
			continue
		source.is_present = true
		source.current = PlayerState.to_int(row.get("current_stamina", 0))
		var recovered_at: Variant = row.get("last_recovery_at", null)
		if recovered_at is String:
			source.recovered_at_unix = ServerDatetime.parse_to_unix(recovered_at)
		source.rate_x100 = _rate_x100(row.get("recovery_rate_multiplier", null))
		break
	return source


## 最大スタミナ。level が無い・行が無い（最大レベル超を含む）・テーブルが無いときは -1。
func _max_stamina(level: int) -> int:
	if level < 0:
		return -1
	var row := _mst_player_level_repository.get_by_level(level)
	if row == null:
		return -1
	return row.max_stamina


## 回復間隔（秒）。値が 1 以上のときだけ有効。それ以外は 0（回復を計算しない）。
func _interval_seconds() -> int:
	var row := _mst_config_repository.get_by_id(PlayerResourceIds.STAMINA_RECOVERY_INTERVAL_KEY)
	if row == null:
		return 0
	var value := row.value_as_int()
	return value if value >= 1 else 0


## 倍率（"1.50" など。数値でも可）を 100 倍の整数にする。読めない・0 以下は 0。
func _rate_x100(raw: Variant) -> int:
	var rate := 0.0
	if raw is String:
		var text: String = raw.strip_edges()
		if not text.is_valid_float():
			return 0
		rate = text.to_float()
	elif raw is int or raw is float:
		rate = float(raw)
	else:
		return 0
	var scaled := roundi(rate * 100.0)
	return scaled if scaled > 0 else 0
