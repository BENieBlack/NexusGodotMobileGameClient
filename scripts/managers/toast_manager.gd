extends Node

# トーストマネージャー - WebSocket（Reverb/Pusherプロトコル）によるリアルタイム通知とトースト表示を管理

# ============================================================
# 定数
# ============================================================
const WS_URL = "ws://localhost:8080/app/nexus-key"
const AUTH_ENDPOINT = "/broadcasting/auth"
const PING_TIMEOUT_SEC = 35.0   # ping未到達でタイムアウトとみなす秒数
const RECONNECT_DELAY_SEC = 3.0 # 再接続待機秒数
const MAX_RECONNECT_ATTEMPTS = 5 # 最大再接続試行回数

# トースト表示時間（秒）
const TOAST_DISPLAY_SEC = 3.0
# トーストアニメーション時間（秒）
const TOAST_ANIM_SEC = 0.3
# トースト上端オフセット（画面外にある状態の Y 位置）
const TOAST_HIDDEN_Y = -160.0
# トースト表示時の Y 位置（画面上部から少し下）
const TOAST_VISIBLE_Y = 60.0

# 通知タイプ → 絵文字アイコンのマッピング
const NOTIFICATION_ICONS = {
	"mission_completed":    "🎯",
	"mission_reward_ready": "🎁",
	"friend_apply_received":"👤",
	"friend_apply_accepted":"✅",
	"guild_apply_received": "🏰",
	"guild_apply_accepted": "✅",
	"guild_apply_rejected": "❌",
	"mailbox_received":     "📬",
	"login_bonus_ready":    "🎊",
	"system_announcement":  "📢",
	"maintenance_notice":   "🔧",
	# ギルド全員向け通知アイコン
	"guild_member_joined":  "🏰",
	"guild_member_left":    "👋",
	"guild_level_up":       "⬆️",
}
const DEFAULT_ICON = "🔔"

# ============================================================
# 内部状態
# ============================================================
var _ws: WebSocketPeer = null
var _socket_id: String = ""
var _is_subscribed: bool = false
var _reconnect_attempts: int = 0
var _reconnect_timer: float = 0.0
var _is_reconnecting: bool = false
var _ping_timer: float = 0.0

# トーストキュー（Dictionary: title, body, type）
var _toast_queue: Array = []
var _is_showing_toast: bool = false

# トースト UI ノード
var _canvas_layer: CanvasLayer = null
var _toast_panel: PanelContainer = null
var _icon_label: Label = null
var _title_label: Label = null
var _body_label: Label = null

# チャンネル認証用の一時 HTTPRequest
var _auth_http: HTTPRequest = null

# ============================================================
# ライフサイクル
# ============================================================
func _ready() -> void:
	_build_toast_ui()
	print("[ToastManager] 初期化完了")

func _process(delta: float) -> void:
	# 再接続待機中
	if _is_reconnecting:
		_reconnect_timer -= delta
		if _reconnect_timer <= 0.0:
			_is_reconnecting = false
			_do_connect()
		return

	# WebSocket が未接続なら何もしない
	if _ws == null:
		return

	_ws.poll()

	var state = _ws.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			_ping_timer += delta
			if _ping_timer >= PING_TIMEOUT_SEC:
				print("[ToastManager] Ping タイムアウト - 再接続")
				_handle_disconnect()
				return
			# 受信パケットを処理
			while _ws.get_available_packet_count() > 0:
				var raw = _ws.get_packet()
				_handle_message(raw.get_string_from_utf8())

		WebSocketPeer.STATE_CLOSING, WebSocketPeer.STATE_CLOSED:
			print("[ToastManager] WebSocket が切断されました")
			_handle_disconnect()

# ============================================================
# 公開メソッド
# ============================================================

## Reverb への接続を開始する（ログイン完了後に呼ぶ）
func connect_to_reverb() -> void:
	_reconnect_attempts = 0
	_do_connect()

## Reverb から切断する
func disconnect_from_reverb() -> void:
	_reconnect_attempts = MAX_RECONNECT_ATTEMPTS  # 再接続しないようにする
	if _ws != null:
		_ws.close()
		_ws = null
	_socket_id = ""
	_is_subscribed = false
	print("[ToastManager] WebSocket を切断しました")

## 手動でトーストを表示する（デバッグ・他シーンからの呼び出し用）
func show_toast(title: String, body: String, type: String = "") -> void:
	_toast_queue.append({"title": title, "body": body, "type": type})
	if not _is_showing_toast:
		_show_next_toast()

## ギルドに加入したときに呼び出す（presence-guild.{guild_id} を購読する）
func subscribe_guild(guild_id: int) -> void:
	if _socket_id == "" or UserDataManager.auth_token == "":
		print("[ToastManager] socket_id またはトークンが未設定のため guild チャンネル購読できません")
		return

	var channel_name = "presence-guild." + str(guild_id)
	print("[ToastManager] ギルドチャンネル認証リクエスト送信: ", channel_name)

	# presence チャンネルも認証が必要なため HTTPRequest で auth を取得する
	var auth_http = HTTPRequest.new()
	add_child(auth_http)
	auth_http.request_completed.connect(func(result, code, _headers, body):
		_on_guild_auth_completed(result, code, body, channel_name, auth_http)
	)

	var url = "http://localhost:8080/broadcasting/auth"
	var headers = PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		"Authorization: Bearer " + UserDataManager.auth_token
	])
	var body = JSON.stringify({
		"socket_id": _socket_id,
		"channel_name": channel_name
	})
	auth_http.request(url, headers, HTTPClient.METHOD_POST, body)

## ギルドから脱退したときに呼び出す（presence-guild.{guild_id} の購読を解除する）
func unsubscribe_guild(guild_id: int) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		print("[ToastManager] WebSocket 未接続のためギルドチャンネル購読解除できません")
		return

	var channel_name = "presence-guild." + str(guild_id)
	var msg = JSON.stringify({
		"event": "pusher:unsubscribe",
		"data": {
			"channel": channel_name
		}
	})
	_ws.send_text(msg)
	print("[ToastManager] ギルドチャンネル購読解除: ", channel_name)

# ============================================================
# WebSocket 接続処理
# ============================================================
func _do_connect() -> void:
	_socket_id = ""
	_is_subscribed = false
	_ping_timer = 0.0

	_ws = WebSocketPeer.new()
	var err = _ws.connect_to_url(WS_URL)
	if err != OK:
		print("[ToastManager] WebSocket 接続失敗: ", err)
		_handle_disconnect()
		return
	print("[ToastManager] WebSocket 接続中: ", WS_URL)

func _handle_disconnect() -> void:
	_ws = null
	_socket_id = ""
	_is_subscribed = false

	if _reconnect_attempts >= MAX_RECONNECT_ATTEMPTS:
		print("[ToastManager] 最大再接続回数に達しました。接続を停止します。")
		return

	_reconnect_attempts += 1
	_reconnect_timer = RECONNECT_DELAY_SEC
	_is_reconnecting = true
	print("[ToastManager] %d 秒後に再接続します（試行 %d/%d）" % [
		RECONNECT_DELAY_SEC, _reconnect_attempts, MAX_RECONNECT_ATTEMPTS
	])

# ============================================================
# メッセージ処理（Pusherプロトコル）
# ============================================================
func _handle_message(raw: String) -> void:
	var msg = JSON.parse_string(raw)
	if msg == null:
		print("[ToastManager] JSONパース失敗: ", raw)
		return

	var event = msg.get("event", "")
	print("[ToastManager] イベント受信: ", event)

	match event:
		"pusher:connection_established":
			_on_connection_established(msg)
		"pusher_internal:subscription_succeeded":
			_on_subscription_succeeded(msg)
		"pusher:ping":
			_send_pong()
		"notification.created":
			_on_notification_created(msg)
		"guild.notification":
			_handle_guild_notification(msg)
		_:
			print("[ToastManager] 未処理のイベント: ", event)

func _on_connection_established(msg: Dictionary) -> void:
	# data フィールドは JSON 文字列なので二重デコード
	var data_raw = msg.get("data", "")
	var data: Dictionary = {}
	if typeof(data_raw) == TYPE_STRING:
		var parsed = JSON.parse_string(data_raw)
		if parsed != null:
			data = parsed
	elif typeof(data_raw) == TYPE_DICTIONARY:
		data = data_raw

	_socket_id = data.get("socket_id", "")
	_reconnect_attempts = 0  # 接続成功で試行回数リセット
	_ping_timer = 0.0
	print("[ToastManager] 接続確立。socket_id: ", _socket_id)

	# プライベートチャンネル認証を行う
	_authenticate_channel()

func _authenticate_channel() -> void:
	if _socket_id == "" or UserDataManager.user_id == "":
		print("[ToastManager] socket_id またはプレイヤーIDが未設定のため認証できません")
		return

	var channel_name = "private-notification." + UserDataManager.user_id

	# 一時 HTTPRequest で認証APIを叩く
	if _auth_http != null:
		_auth_http.queue_free()
	_auth_http = HTTPRequest.new()
	add_child(_auth_http)
	_auth_http.request_completed.connect(func(result, code, _headers, body):
		_on_auth_completed(result, code, body, channel_name)
	)

	var url = "http://localhost:8080/broadcasting/auth"
	var headers = PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		"Authorization: Bearer " + UserDataManager.auth_token
	])
	var body = JSON.stringify({
		"socket_id": _socket_id,
		"channel_name": channel_name
	})

	print("[ToastManager] チャンネル認証リクエスト送信: ", channel_name)
	_auth_http.request(url, headers, HTTPClient.METHOD_POST, body)

func _on_auth_completed(result: int, code: int, body: PackedByteArray, channel_name: String) -> void:
	if _auth_http != null:
		_auth_http.queue_free()
		_auth_http = null

	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[ToastManager] チャンネル認証失敗: result=", result, " code=", code)
		return

	var res = JSON.parse_string(body.get_string_from_utf8())
	if res == null:
		print("[ToastManager] 認証レスポンスのパース失敗")
		return

	var auth_str = res.get("auth", "")
	if auth_str == "":
		print("[ToastManager] auth が空です")
		return

	print("[ToastManager] チャンネル認証成功。subscribe 送信: ", channel_name)
	_subscribe_channel(channel_name, auth_str)

func _subscribe_channel(channel_name: String, auth_str: String) -> void:
	var msg = JSON.stringify({
		"event": "pusher:subscribe",
		"data": {
			"channel": channel_name,
			"auth": auth_str
		}
	})
	_ws.send_text(msg)

func _on_subscription_succeeded(msg: Dictionary) -> void:
	_is_subscribed = true
	var channel = msg.get("channel", "")
	print("[ToastManager] チャンネル購読成功: ", channel)

	# プライベート通知チャンネルの購読成功後、ギルドに加入中であれば自動購読する
	if channel.begins_with("private-notification."):
		var gid = UserDataManager.guild_id
		if gid > 0:
			print("[ToastManager] ギルドチャンネルを自動購読します: guild_id=", gid)
			subscribe_guild(gid)

func _send_pong() -> void:
	_ping_timer = 0.0  # タイムアウトタイマーをリセット
	var msg = JSON.stringify({"event": "pusher:pong", "data": {}})
	_ws.send_text(msg)
	print("[ToastManager] Pong 送信")

func _on_notification_created(msg: Dictionary) -> void:
	# data フィールドは JSON 文字列の場合があるので二重デコード
	var data_raw = msg.get("data", "")
	var data: Dictionary = {}
	if typeof(data_raw) == TYPE_STRING:
		var parsed = JSON.parse_string(data_raw)
		if parsed != null:
			data = parsed
	elif typeof(data_raw) == TYPE_DICTIONARY:
		data = data_raw

	var title = data.get("title", "通知")
	var body = data.get("body", "")
	var type = data.get("type", "")

	print("[ToastManager] 通知受信: [%s] %s - %s" % [type, title, body])
	show_toast(title, body, type)

# ギルドチャンネル認証完了時の処理
func _on_guild_auth_completed(result: int, code: int, body: PackedByteArray, channel_name: String, auth_http: HTTPRequest) -> void:
	auth_http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[ToastManager] ギルドチャンネル認証失敗: result=", result, " code=", code)
		return

	var res = JSON.parse_string(body.get_string_from_utf8())
	if res == null:
		print("[ToastManager] ギルドチャンネル認証レスポンスのパース失敗")
		return

	var auth_str = res.get("auth", "")
	if auth_str == "":
		print("[ToastManager] ギルドチャンネル認証: auth が空です")
		return

	print("[ToastManager] ギルドチャンネル認証成功。subscribe 送信: ", channel_name)
	_subscribe_channel(channel_name, auth_str)

# guild.notification イベントを受信したときの処理
func _handle_guild_notification(msg: Dictionary) -> void:
	# data フィールドは JSON 文字列の場合があるので二重デコード
	var data_raw = msg.get("data", "")
	var data: Dictionary = {}
	if typeof(data_raw) == TYPE_STRING:
		var parsed = JSON.parse_string(data_raw)
		if parsed != null:
			data = parsed
	elif typeof(data_raw) == TYPE_DICTIONARY:
		data = data_raw

	var title = data.get("title", "ギルド通知")
	var body = data.get("body", "")
	var type = data.get("type", "")

	print("[ToastManager] ギルド通知受信: [%s] %s - %s" % [type, title, body])
	show_toast(title, body, type)

# ============================================================
# トースト UI 構築
# ============================================================
func _build_toast_ui() -> void:
	# CanvasLayer（最前面に常時表示）
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 100  # 高いレイヤーで最前面
	add_child(_canvas_layer)

	# PanelContainer（トースト本体）
	_toast_panel = PanelContainer.new()
	_toast_panel.name = "ToastPanel"
	# 画面上部中央に配置
	_toast_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast_panel.custom_minimum_size = Vector2(800, 0)
	_toast_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toast_panel.position = Vector2(0, TOAST_HIDDEN_Y)
	_toast_panel.visible = false
	_canvas_layer.add_child(_toast_panel)

	# HBoxContainer
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.add_child(hbox)
	_toast_panel.add_child(margin)

	# IconLabel（絵文字アイコン）
	_icon_label = Label.new()
	_icon_label.name = "IconLabel"
	_icon_label.add_theme_font_size_override("font_size", 48)
	_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(_icon_label)

	# VBoxContainer（テキスト部分）
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	# TitleLabel
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.add_theme_font_size_override("font_size", 36)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_title_label)

	# BodyLabel
	_body_label = Label.new()
	_body_label.name = "BodyLabel"
	_body_label.add_theme_font_size_override("font_size", 28)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(_body_label)

# ============================================================
# トースト表示・アニメーション
# ============================================================
func _show_next_toast() -> void:
	if _toast_queue.is_empty():
		_is_showing_toast = false
		return

	_is_showing_toast = true
	var item = _toast_queue.pop_front()
	_display_toast(item["title"], item["body"], item["type"])

func _display_toast(title: String, body: String, type: String) -> void:
	# アイコン設定
	_icon_label.text = NOTIFICATION_ICONS.get(type, DEFAULT_ICON)
	_title_label.text = title
	_body_label.text = body

	# 初期位置を画面外（上）に設定して表示
	_toast_panel.position.y = TOAST_HIDDEN_Y
	_toast_panel.visible = true

	# スライドインアニメーション
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_toast_panel, "position:y", TOAST_VISIBLE_Y, TOAST_ANIM_SEC)
	await tween.finished

	# 表示時間待機
	await get_tree().create_timer(TOAST_DISPLAY_SEC).timeout

	# スライドアウトアニメーション
	var tween_out = create_tween()
	tween_out.set_ease(Tween.EASE_IN)
	tween_out.set_trans(Tween.TRANS_CUBIC)
	tween_out.tween_property(_toast_panel, "position:y", TOAST_HIDDEN_Y, TOAST_ANIM_SEC)
	await tween_out.finished

	_toast_panel.visible = false

	# 次のトーストを表示
	_show_next_toast()
