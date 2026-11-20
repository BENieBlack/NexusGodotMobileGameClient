## アイコンの確認用の一覧画面（debug 専用。製品の複製には入らない。client_design.md 5-6・要件 I12）。
##
## 目的: 同梱した全アイコンを 1 枚に並べ、画風・大きさ・フォールバックを目で確かめる。マスターに在るのに
##       絵が無い ID（足し忘れ）は赤く出す。
## 使い方:
##   godot --path . res://debug/icon_gallery.tscn                      … ウィンドウで見る
##   godot --path . res://debug/icon_gallery.tscn -- --e2e-shot=<dir>
##     … 1 枚に撮って終了（<dir>/icon_gallery.png。ヘッドレスでは描画されないので撮れない）
## 流れ:
##   1. ItemIconTable の全キーを、実際の表示サイズ（80）の ItemIcon で並べる（ItemIcon 経由なので、
##      ホーム・ログインボーナスと同じ読み込みの経路を確かめられる）
##   2. 端末に取得済みのマスター（user://master/ の mst_item のファイル）があれば ID を読み、絵が無い ID を赤く出す。
##      無ければ「マスター未取得」と出す（master_data/ は変えない。ここだけの読み取り。全件を返す口が Repository に無いため）
##   3. --e2e-shot があれば、描画が落ち着いたら 1 枚に保存して終了する
extends Control

## 1 行に並べるマスの数と、マスの大きさ（ビューポート単位。1080 幅に収まる）
const COLUMNS := 6
const CELL_SIZE := Vector2(160, 150)
## 絵の表示サイズ（カレンダーの通常のマスと同じ 80）
const ICON_SIZE := 80
## 撮影までの待ち（秒。レイアウトが落ち着いてから）
const SHOT_DELAY := 0.6
## 取得済みの mst_item のファイル名（user://master/mst_item_<sha256 の 64 桁>.sqlite。`mst_item__l10n_…` は含まない）
const MASTER_FILE_PATTERN := "^mst_item_[0-9a-f]{64}\\.sqlite$"
const MASTER_DIR := "user://master"

var _shot_dir: String = ""
var _elapsed: float = 0.0
var _shot_done: bool = false


func _ready() -> void:
	_shot_dir = _shot_dir_from_args(OS.get_cmdline_user_args() + OS.get_cmdline_args())
	var background := ColorRect.new()
	background.color = Color(0.1, 0.1, 0.25)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	root.add_child(_label("アイコン一覧（%d 点）" % ItemIconTable.keys().size(), 36, Color.WHITE))

	# --- 1. 全キーを並べる ---
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	root.add_child(grid)
	for key: String in ItemIconTable.keys():
		grid.add_child(_cell(key, Color.WHITE))

	# --- 2. マスターに在って絵が無い ID を赤く出す ---
	var master_ids := _read_master_item_ids()
	var table_keys: Array[String] = []
	for key: String in ItemIconTable.keys():
		table_keys.append(key)
	if master_ids.is_empty():
		root.add_child(_label("マスター未取得（mst_item を読めない）。絵の不足の検査はできません", 24, Color.YELLOW))
	else:
		var missing := missing_ids(table_keys, master_ids)
		if missing.is_empty():
			root.add_child(
				_label("マスターの mst_item %d 行すべてに絵があります" % master_ids.size(), 24, Color.LIGHT_GREEN)
			)
		else:
			root.add_child(_label("絵が無い ID（%d 件）" % missing.size(), 28, Color.RED))
			var missing_grid := GridContainer.new()
			missing_grid.columns = COLUMNS
			root.add_child(missing_grid)
			for item_id: String in missing:
				# 在る絵が無いので、ItemIcon は unknown を出す（実際の画面と同じ見え方）
				missing_grid.add_child(_cell("items/" + item_id, Color.RED, item_id))


func _process(delta: float) -> void:
	if _shot_dir == "" or _shot_done:
		return
	_elapsed += delta
	if _elapsed < SHOT_DELAY:
		return
	_shot_done = true
	var texture := get_viewport().get_texture()
	if texture != null:
		DirAccess.make_dir_recursive_absolute(_shot_dir)
		var path := _shot_dir.path_join("icon_gallery.png")
		print("E2E: スクリーンショット ", path, " (", texture.get_image().save_png(path), ")")
	get_tree().quit(0)


## マス 1 つ（絵＋キーの名前）。key が items/<id> ならその ID で、それ以外（fallback/ ・ui/）はキーの絵を直接出す。
func _cell(key: String, color: Color, caption: String = "") -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = CELL_SIZE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon: ItemIcon = load("res://core/presentation/item_icon/item_icon.tscn").instantiate()
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if key.begins_with(ItemIconResolver.ITEMS_PREFIX):
		icon.setup("item", key.trim_prefix(ItemIconResolver.ITEMS_PREFIX), "", ICON_SIZE)
	else:
		# fallback/・ui/ は ItemIcon の入口（type・id）では引けないので、表の絵を直接入れる
		icon.setup("unit", "", "", ICON_SIZE)
		icon.texture = ItemIconTable.texture_of(key)
	box.add_child(icon)
	var text := caption if caption != "" else key.get_slice("/", 1)
	var name_label := _label(text, 16, color)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(name_label)
	return box


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## マスターの ID のうち、`items/<id>` の絵が表に無いもの（足し忘れ）。純粋関数（テストする）。
static func missing_ids(table_keys: Array[String], master_ids: Array[String]) -> Array[String]:
	var missing: Array[String] = []
	for item_id in master_ids:
		if not table_keys.has(ItemIconResolver.ITEMS_PREFIX + item_id):
			missing.append(item_id)
	return missing


## 引数から --e2e-shot=<dir> の <dir> を取り出す（無ければ空）。
static func _shot_dir_from_args(args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with("--e2e-shot="):
			return arg.trim_prefix("--e2e-shot=")
	return ""


## 取得済みのマスター（user://master/ の mst_item のファイル）から ID を読む。読めなければ空。
## 配信のファイルは版ごとのハッシュ付きの名前で複数残りうるので、更新日時が新しいものを使う。
func _read_master_item_ids() -> Array[String]:
	var ids: Array[String] = []
	if not ClassDB.class_exists("SQLite"):
		return ids
	var regex := RegEx.create_from_string(MASTER_FILE_PATTERN)
	var newest := ""
	var newest_time := -1
	for file_name in DirAccess.get_files_at(MASTER_DIR):
		if regex.search(file_name) == null:
			continue
		var path := MASTER_DIR.path_join(file_name)
		var modified := FileAccess.get_modified_time(path)
		if modified > newest_time:
			newest = path
			newest_time = modified
	if newest == "":
		return ids
	var database: Object = ClassDB.instantiate("SQLite")
	database.path = newest
	if not database.open_db():
		return ids
	if database.query("SELECT id FROM mst_item ORDER BY id"):
		for row in database.query_result:
			ids.append(str(row["id"]))
	database.close_db()
	return ids
