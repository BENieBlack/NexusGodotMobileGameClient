extends SceneTree

# X-Master-Update-Requiredの判定テスト
func _init() -> void:
	var api_client_script = load("res://scripts/services/api_client.gd")
	var api_client = api_client_script.new()

	assert(api_client._has_master_update_required(PackedStringArray([
		"Content-Type: application/json",
		"X-Master-Update-Required: true",
	])), "trueの更新要求ヘッダーを検出できること")

	assert(api_client._has_master_update_required(PackedStringArray([
		"x-master-update-required: 1",
	])), "大文字小文字を区別せず1を検出できること")

	assert(not api_client._has_master_update_required(PackedStringArray([
		"X-Master-Update-Required: false",
	])), "falseでは更新要求にならないこと")

	assert(not api_client._has_master_update_required(PackedStringArray([
		"Content-Type: application/json",
	])), "対象ヘッダーがない場合は更新要求にならないこと")

	api_client.free()
	quit()
