## ApplyLoginDataUseCase の単体テスト。メモリのみの LocalPlayerRepository を使う（偽物にするほどの中身が無い）。
extends GdUnitTestSuite

var _repository: LocalPlayerRepository
var _use_case: ApplyLoginDataUseCase


func before_test() -> void:
	_repository = LocalPlayerRepository.new()
	_use_case = ApplyLoginDataUseCase.new(_repository)


## 前提: sys_player と 6 種の一覧。操作: handle。
## 期待: プレイヤー ID（my_id）と 6 種すべてが読み取りモデルから読める。
func test_applies_player_and_six_lists() -> void:
	var lists := {}
	for key in PlayerState.TRX_LIST_KEYS:
		lists[key] = [{"k": key}]
	var result := _use_case.handle({"my_id": "abc", "level": 3}, lists)

	assert_bool(result.ok).is_true()
	var state := _repository.current()
	assert_str(state.user_id()).is_equal("abc")
	assert_int(int(state.sys_player["level"])).is_equal(3)
	for key in PlayerState.TRX_LIST_KEYS:
		assert_int(state.trx_list(key).size()).is_equal(1)


## 前提: 6 種のうち一部のキーが欠けている・Array でない値が混ざる。操作: handle。
## 期待: 欠けたキーは空配列で補い、読む側が「キーが無い」を気にしなくてよい。
func test_missing_lists_are_filled_with_empty_arrays() -> void:
	_use_case.handle({"my_id": "abc"}, {"trx_unit_list": [{"x": 1}], "trx_item_list": "bad"})
	var state := _repository.current()
	assert_int(state.trx_list("trx_unit_list").size()).is_equal(1)
	assert_array(state.trx_list("trx_item_list")).is_empty()
	assert_array(state.trx_list("trx_stamina_list")).is_empty()


## 前提: 2 回 handle（別の内容）。期待: 差分でなく全量で置き換わる。
func test_second_apply_replaces_everything() -> void:
	_use_case.handle({"my_id": "a"}, {"trx_unit_list": [{"x": 1}]})
	_use_case.handle({"my_id": "b"}, {})
	assert_str(_repository.current().user_id()).is_equal("b")
	assert_array(_repository.current().trx_list("trx_unit_list")).is_empty()


## 前提: データを保持。操作: clear。期待: 空の状態に戻る（セッション破棄）。
func test_clear_empties_state() -> void:
	_use_case.handle({"my_id": "a"}, {"trx_unit_list": [{"x": 1}]})
	_repository.clear()
	assert_bool(_repository.current().is_empty()).is_true()
