extends Control

# 利用規約同意画面

@onready var agreement_list: VBoxContainer = $VBoxContainer/ScrollContainer/AgreementList
@onready var agree_all_button: Button = $VBoxContainer/AgreeAllButton

# APIクライアント（未同意規約取得用）
var _api_client_pending: Node
# APIクライアント（同意送信用）
var _api_client_consent: Node

# 未同意の規約リスト
var _pending_agreements: Array[SysAgreement] = []
# 同意済みインデックス
var _consent_index: int = 0

func _ready() -> void:
	print("利用規約同意画面を表示")

	# 未同意規約取得用APIクライアントを作成
	_api_client_pending = preload("res://scripts/services/api_client.gd").new()
	add_child(_api_client_pending)
	_api_client_pending.request_completed.connect(_on_pending_completed)
	_api_client_pending.request_failed.connect(_on_pending_failed)
	_api_client_pending.business_error.connect(_on_business_error)

	# 同意送信用APIクライアントを作成
	_api_client_consent = preload("res://scripts/services/api_client.gd").new()
	add_child(_api_client_consent)
	_api_client_consent.request_completed.connect(_on_consent_completed)
	_api_client_consent.request_failed.connect(_on_consent_failed)
	_api_client_consent.business_error.connect(_on_consent_business_error)

	agree_all_button.text = "すべての規約に同意して続ける"
	agree_all_button.pressed.connect(_on_agree_all_button_pressed)

	# 未同意規約を取得
	_api_client_pending.get_request("/agreement/pending")

# 未同意規約取得成功時
func _on_pending_completed(response_data: Dictionary) -> void:
	var raw_list: Array = response_data.get("agreement_list", [])
	print("未同意規約取得完了: ", raw_list.size(), "件")

	if raw_list.is_empty():
		# 未同意規約なし → 次のシーンへ遷移
		print("未同意規約なし - ログインボーナス画面へ遷移")
		SceneManager.goto_login_bonus()
		return

	# 規約カードを表示
	for item in raw_list:
		var agreement = SysAgreement.from_dict(item)
		_pending_agreements.append(agreement)
		_add_agreement_card(agreement)

# 未同意規約取得失敗時
func _on_pending_failed(error: String) -> void:
	print("未同意規約取得失敗: ", error)
	# エラー時はスキップしてログインボーナス画面へ
	SceneManager.goto_login_bonus()

# ビジネスエラー時（pending）
func _on_business_error(error_code: int, message: String) -> void:
	print("利用規約取得ビジネスエラー (", error_code, "): ", message)
	SceneManager.goto_login_bonus()

# 規約カードをリストに追加
func _add_agreement_card(agreement: SysAgreement) -> void:
	var card = HBoxContainer.new()

	# 規約タイトル + バージョン
	var name_label = Label.new()
	name_label.text = agreement.title + " v" + agreement.version
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(name_label)

	# "確認する" ボタン
	var open_button = Button.new()
	open_button.text = "確認する"
	open_button.pressed.connect(func() -> void:
		print("規約URLを開く: ", agreement.url)
		OS.shell_open(agreement.url)
	)
	card.add_child(open_button)

	agreement_list.add_child(card)

# "すべての規約に同意して続ける" ボタン押下時
func _on_agree_all_button_pressed() -> void:
	if _pending_agreements.is_empty():
		SceneManager.goto_login_bonus()
		return

	agree_all_button.disabled = true
	_consent_index = 0
	_send_next_consent()

# 次の規約に同意を送信
func _send_next_consent() -> void:
	if _consent_index >= _pending_agreements.size():
		# 全件同意完了 → ログインボーナス画面へ遷移
		print("全規約への同意完了 - ログインボーナス画面へ遷移")
		SceneManager.goto_login_bonus()
		return

	var agreement = _pending_agreements[_consent_index]
	print("規約に同意送信: id=", agreement.sys_agreement_id)
	_api_client_consent.post_request("/agreement/consent", {
		"sys_agreement_id": agreement.sys_agreement_id
	})

# 同意送信成功時
func _on_consent_completed(_response_data: Dictionary) -> void:
	print("同意送信完了: index=", _consent_index)
	_consent_index += 1
	_send_next_consent()

# 同意送信失敗時
func _on_consent_failed(error: String) -> void:
	print("同意送信失敗: ", error)
	agree_all_button.disabled = false

# 同意送信ビジネスエラー時
func _on_consent_business_error(error_code: int, message: String) -> void:
	print("同意ビジネスエラー (", error_code, "): ", message)
	# 24002（既に同意済み）は次へ進む
	if error_code == 24002:
		_consent_index += 1
		_send_next_consent()
	else:
		agree_all_button.disabled = false
