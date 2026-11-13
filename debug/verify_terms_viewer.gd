## 規約の閲覧（取得 → BBCode への変換 → RichTextLabel への描画）を、実サーバーに対して確かめる検証用シーン。
##
## 目的: 単体テストは通信を差し替えているので、サーバーの public/terms に置いた HTML を本当に取得でき、
##       変換して画面に描けることを 1 回確認する。製品コードではない（debug/ はエクスポート除外）。
##       サインアップはしない（規約の HTML は認証なしの GET）ので、sign_up の回数制限を使わない。
## 使い方（シーンとして実行する。autoload の AppContext が要るため -s のスクリプト実行では動かない）:
##   godot --path . --resolution 540x960 res://debug/verify_terms_viewer.tscn -- <出力ディレクトリ> [URL...]
##   URL の既定は /legal/terms-of-service-1.0.0.html と /legal/privacy-policy-1.0.0.html。
##   向き先は ApiConfig（環境変数 NEXUS_API_BASE_URL など）。ヘッドレスでは画像を保存できない。
## 出力: 取得の成否、HTML と BBCode の文字数、描画した本文の行数、保存した画像のパス、最後に VERIFY_RESULT。
## 終了コード: すべて表示できたら 0、1 つでも失敗したら 1。
extends Node

const VIEWER_SCENE := "res://contexts/agreement/presentation/terms_viewer/terms_viewer.tscn"
const DEFAULT_URLS := ["/legal/terms-of-service-1.0.0.html", "/legal/privacy-policy-1.0.0.html"]

var _failed: bool = false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else ""
	var urls: Array = DEFAULT_URLS if args.size() <= 1 else args.slice(1)
	var use_case := AppContext.fetch_agreement_document_use_case()

	for url in urls:
		await _verify(use_case, str(url), out_dir)
	print("VERIFY_RESULT: ", "NG" if _failed else "OK")
	get_tree().quit(1 if _failed else 0)


func _verify(use_case: FetchAgreementDocumentUseCase, url: String, out_dir: String) -> void:
	# --- 1. 取得と変換（画面を通さず UseCase だけで） ---
	var fetched := await use_case.handle(url)
	if not fetched.ok:
		print("NG fetch ", url, " kind=", fetched.error.kind)
		_failed = true
		return
	var bbcode := HtmlToBbcode.to_bbcode(fetched.html)
	print("OK fetch ", url, " html=", fetched.html.length(), " bbcode=", bbcode.length())
	if bbcode == "" or bbcode.contains("</"):
		print("NG convert: 空、またはタグが残っている")
		_failed = true

	# --- 2. 画面に描く ---
	var viewer: TermsViewerPresenter = load(VIEWER_SCENE).instantiate()
	viewer.setup(use_case, url.get_file(), url)
	add_child(viewer)
	for i in range(120):
		await get_tree().process_frame
		if (viewer.get_node("VBoxContainer/StatusLabel") as Label).text != "読み込み中...":
			break
	var status := (viewer.get_node("VBoxContainer/StatusLabel") as Label).text
	var body := viewer.get_node("VBoxContainer/BodyLabel") as RichTextLabel
	await get_tree().process_frame
	await get_tree().process_frame
	var parsed := body.get_parsed_text()
	print(
		"render: status='",
		status,
		"' lines=",
		body.get_line_count(),
		" 先頭=",
		parsed.substr(0, 20).replace("\n", "/")
	)
	if status != "" or body.get_line_count() < 3:
		_failed = true

	# --- 3. 画像（先頭と、下へスクロールした所） ---
	if out_dir != "" and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var base := url.get_file().get_basename()
		_save(out_dir + "/" + base + "_top.png")
		var bar := body.get_v_scroll_bar()
		bar.value = bar.page * 1.2
		await get_tree().process_frame
		await get_tree().process_frame
		_save(out_dir + "/" + base + "_scrolled.png")
	viewer.queue_free()
	await get_tree().process_frame


func _save(path: String) -> void:
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path, " (", error, ")")
