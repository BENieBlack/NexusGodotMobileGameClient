## 規約の HTML（許可したタグだけのサブセット）を、RichTextLabel の BBCode に変換する純粋関数のクラス。
##
## 目的: 規約を WebView なしで Godot の画面に描くため、サーバーの public に置いた HTML を BBCode にする。
##       状態を持つのは 1 回の変換の間だけ（to_bbcode が毎回 new する）。Node・通信に依存しないので単体テストできる。
## 使い方: var bbcode := HtmlToBbcode.to_bbcode(html)
## 対応するタグ:
##   h1 h2 h3        大きさ（HEADING_SIZES）と太字。前後に空行
##   p               段落（前後に空行）        br  改行
##   ul ol li        箇条書き（• ）と番号（1. ）。入れ子は 4 文字ずつ字下げ
##   strong b / em i 太字 / 斜体
##   a href          [url=...]（http / https の href だけ。それ以外はタグを捨てて文字だけ残す）
##   hr              区切り線
##   div section article header footer main   中身はそのまま、前後で改行するだけ（段落の区切りに使われやすいため）
## 捨てるもの: <head> <title> <script> <style>（中身ごと）、コメント、DOCTYPE、未対応のタグ（中身の文字は残す）。
## エスケープ: 本文の "[" "]" は BBCode として解釈されないよう [lb] [rb] にする。HTML エンティティ
##   （&amp; &lt; &gt; &quot; &apos; &nbsp; ほか少数の名前つき、&#数字; &#x16進;）は 1 回だけデコードする
##   （&amp;lt; が < にならない）。href の "[" "]" は %5B %5D にして [url] を壊させない。
## 空白: 連続する空白・改行は 1 つにまとめ、行頭と行末の空白は捨てる（HTML と同じ見え方）。
class_name HtmlToBbcode
extends RefCounted

## 見出しの文字サイズ（本文は画面側の RichTextLabel が決める）
const HEADING_SIZES := {"h1": 44, "h2": 36, "h3": 32}
## リンクの色（暗い背景で読める明るさ）
const LINK_COLOR := "#6db3ff"
const RULE_BBCODE := "[color=#777777][hr][/color]"
## 中身はそのままで、前後だけ改行するタグ
const BLOCK_TAGS := ["div", "section", "article", "header", "footer", "main"]
const NAMED_ENTITIES := {
	"amp": "&",
	"lt": "<",
	"gt": ">",
	"quot": '"',
	"apos": "'",
	"nbsp": "\u00a0",
	"copy": "\u00a9",
	"yen": "\u00a5",
	"hellip": "\u2026",
	"mdash": "\u2014",
	"ndash": "\u2013",
	"middot": "\u00b7",
}

## 変換結果
var _out: String = ""
## 次に文字・タグを出すとき、その前に入れる改行の数（ブロックの区切り。1 = 改行、2 = 空行）
var _pending_breaks: int = 0
## 行頭か（行頭の空白を捨てるため）
var _at_line_start: bool = true
## 開いている要素の、閉じる BBCode。{name: 正規化したタグ名, close: 閉じる BBCode}
var _open: Array[Dictionary] = []
## 開いている ul / ol。"ul" か、番号つきの ol は {"ol": 次の番号}
var _lists: Array = []


## HTML を BBCode にする。空・空白だけの入力は空文字。
static func to_bbcode(html: String) -> String:
	return HtmlToBbcode.new()._run(html)


func _run(html: String) -> String:
	# --- 1. 丸ごと捨てるもの（中身ごと）を先に除く ---
	var source := _strip_discarded(html)

	# --- 2. タグと本文に分けて順に処理する ---
	var pos := 0
	while pos < source.length():
		var lt := source.find("<", pos)
		if lt < 0:
			_add_text(source.substr(pos))
			break
		# "<" の次がタグの形（英字か /）でなければ、ただの "<" として本文にする（例: 1 < 2）
		var next := source.substr(lt + 1, 1)
		var is_tag := next == "/" or (next.length() == 1 and next.to_lower() != next.to_upper())
		if not is_tag:
			_add_text(source.substr(pos, lt + 1 - pos))
			pos = lt + 1
			continue
		var gt := _find_tag_end(source, lt)
		if gt < 0:
			# 閉じていないタグ。残りを本文として扱う
			_add_text(source.substr(pos))
			break
		_add_text(source.substr(pos, lt - pos))
		_handle_tag(source.substr(lt + 1, gt - lt - 1))
		pos = gt + 1

	# --- 3. 閉じ忘れを閉じ、整える ---
	while not _open.is_empty():
		_out += _open.pop_back()["close"]
	return _tidy(_out)


## コメント・DOCTYPE・head・title・script・style を除く。閉じタグの無い script / style は末尾まで除く
## （そのまま本文に出すと、コードが規約として表示されるため）。
func _strip_discarded(html: String) -> String:
	var text := _regex_replace("(?s)<!--.*?(-->|$)", html)
	text = _regex_replace("(?i)<!doctype[^>]*>", text)
	text = _regex_replace("(?is)<(script|style|head|title)\\b[^>]*>.*?</\\1\\s*>", text)
	text = _regex_replace("(?is)<(script|style)\\b.*$", text)
	return text


func _regex_replace(pattern: String, text: String) -> String:
	var regex := RegEx.create_from_string(pattern)
	return regex.sub(text, "", true)


## "<" の位置から、タグを閉じる ">" の位置を返す。属性値の引用符の中の ">" は数えない。無ければ -1。
func _find_tag_end(source: String, lt: int) -> int:
	var quote := ""
	for i in range(lt + 1, source.length()):
		var c := source[i]
		if quote != "":
			if c == quote:
				quote = ""
		elif c == '"' or c == "'":
			quote = c
		elif c == ">":
			return i
	return -1


## タグ 1 つ（"<" と ">" の間の文字列）を処理する。
func _handle_tag(inner: String) -> void:
	var is_closing := inner.begins_with("/")
	var body := inner.substr(1) if is_closing else inner
	var name_end := 0
	while name_end < body.length() and _is_name_char(body[name_end]):
		name_end += 1
	var tag_name := body.substr(0, name_end).to_lower()
	if is_closing:
		_close_tag(tag_name)
	else:
		_open_tag(tag_name, body.substr(name_end))


func _is_name_char(c: String) -> bool:
	return (c.to_lower() != c.to_upper()) or (c >= "0" and c <= "9")


func _open_tag(tag_name: String, attributes: String) -> void:
	match tag_name:
		"h1", "h2", "h3":
			_break(2)
			_push(tag_name, "[font_size=%d][b]" % HEADING_SIZES[tag_name], "[/b][/font_size]")
		"p":
			_break(2)
		"br":
			_flush_breaks()
			_out += "\n"
			_at_line_start = true
		"strong", "b":
			_push("b", "[b]", "[/b]")
		"em", "i":
			_push("i", "[i]", "[/i]")
		"a":
			var href := _safe_href(attributes)
			if href == "":
				# リンクにできない <a> は、対の </a> を取り違えないよう空の要素として積む
				_push("a", "", "")
			else:
				_push("a", "[url=%s][color=%s]" % [href, LINK_COLOR], "[/color][/url]")
		"ul":
			_break(2 if _lists.is_empty() else 1)
			_lists.append("ul")
		"ol":
			_break(2 if _lists.is_empty() else 1)
			_lists.append({"ol": 1})
		"li":
			_open_list_item()
		"hr":
			_break(2)
			_flush_breaks()
			_out += RULE_BBCODE
			_break(2)
		_:
			if BLOCK_TAGS.has(tag_name):
				_break(1)
			# それ以外の未対応のタグは捨てる（中身の文字は残る）


func _close_tag(tag_name: String) -> void:
	match tag_name:
		"h1", "h2", "h3":
			_pop_to(tag_name)
			_break(2)
		"p":
			_break(2)
		"strong", "b":
			_pop_to("b")
		"em", "i":
			_pop_to("i")
		"a":
			_pop_to("a")
		"ul", "ol":
			if not _lists.is_empty():
				_lists.pop_back()
			_break(2 if _lists.is_empty() else 1)
		"li":
			_break(1)
		_:
			if BLOCK_TAGS.has(tag_name):
				_break(1)


## li の先頭に付ける記号（• か番号）を出す。ul / ol の外の li は箇条書きとして扱う。
func _open_list_item() -> void:
	_break(1)
	_flush_breaks()
	var depth := maxi(_lists.size(), 1)
	var marker := "• "
	if not _lists.is_empty() and _lists.back() is Dictionary:
		var list: Dictionary = _lists.back()
		marker = "%d. " % int(list["ol"])
		list["ol"] = int(list["ol"]) + 1
	_out += "    ".repeat(depth - 1) + marker
	_at_line_start = false


## href 属性を取り出し、http / https のときだけ [url] に入れてよい形で返す。それ以外は空文字。
func _safe_href(attributes: String) -> String:
	var regex := RegEx.create_from_string(
		"(?is)\\bhref\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
	)
	var found := regex.search(attributes)
	if found == null:
		return ""
	var raw := ""
	for group in range(1, 4):
		if found.get_string(group) != "":
			raw = found.get_string(group)
			break
	var href := _decode_entities(raw).strip_edges()
	var lower := href.to_lower()
	if not (lower.begins_with("http://") or lower.begins_with("https://")):
		return ""
	# [url=...] を壊す文字（角括弧・空白）は符号化する
	return href.replace("[", "%5B").replace("]", "%5D").replace(" ", "%20")


## 開いた要素を積む。開くタグは、保留中の改行を出してから書く（改行より前にタグが来ないように）。
func _push(tag_name: String, open_bbcode: String, close_bbcode: String) -> void:
	_flush_breaks()
	_out += open_bbcode
	_open.append({"name": tag_name, "close": close_bbcode})


## 指定の要素が開いていれば、それまでに開いた要素ごと閉じる（入れ子の食い違いを BBCode に持ち込まない）。
## 開いていなければ何もしない（対応しない閉じタグは無視）。
func _pop_to(tag_name: String) -> void:
	var index := -1
	for i in range(_open.size() - 1, -1, -1):
		if _open[i]["name"] == tag_name:
			index = i
			break
	if index < 0:
		return
	while _open.size() > index:
		_out += _open.pop_back()["close"]


## ブロックの区切りを予約する（実際の改行は、次に文字かタグを出すときに入れる）。
func _break(count: int) -> void:
	_pending_breaks = maxi(_pending_breaks, count)
	_at_line_start = true


## 予約した改行を出す。先頭では出さない（結果が空行から始まらないように）。
func _flush_breaks() -> void:
	if _out != "" and _pending_breaks > 0:
		_out += "\n".repeat(_pending_breaks)
	_pending_breaks = 0


## 本文を 1 つ足す。エンティティをデコード → 空白をまとめる → 角括弧をエスケープする。
func _add_text(raw: String) -> void:
	if raw == "":
		return
	var text := _decode_entities(raw)
	# 通常の空白だけをまとめる（&nbsp; = U+00A0 は残す）
	text = RegEx.create_from_string("[ \\t\\r\\n]+").sub(text, " ", true)
	if _at_line_start:
		text = text.lstrip(" ")
	if text == "":
		return
	_flush_breaks()
	_out += _escape_brackets(text)
	_at_line_start = false


## 本文の角括弧を [lb] [rb] にする。"[" を先に置き換えると、できた "[lb]" の "]" を次の置き換えが
## 壊すので、"]" を一度目印の文字に退避してから戻す。
func _escape_brackets(text: String) -> String:
	const MARK := "\u0001"
	return text.replace("]", MARK).replace("[", "[lb]").replace(MARK, "[rb]")


## HTML エンティティを 1 回だけデコードする。知らない名前・不正な数値はそのまま残す。
func _decode_entities(text: String) -> String:
	if not text.contains("&"):
		return text
	var result := ""
	var pos := 0
	while pos < text.length():
		var amp := text.find("&", pos)
		if amp < 0:
			result += text.substr(pos)
			break
		result += text.substr(pos, amp - pos)
		var semi := text.find(";", amp)
		# エンティティは短い。遠くの ; まで探して本文を巻き込まない
		if semi < 0 or semi - amp > 10:
			result += "&"
			pos = amp + 1
			continue
		var decoded := _decode_entity(text.substr(amp + 1, semi - amp - 1))
		if decoded == "":
			result += "&"
			pos = amp + 1
		else:
			result += decoded
			pos = semi + 1
	return result


## "amp" や "#169"・"#xA9" のような ; の手前の部分を文字にする。分からなければ空文字。
func _decode_entity(entity: String) -> String:
	if entity.begins_with("#"):
		var is_hex := entity.begins_with("#x") or entity.begins_with("#X")
		var digits := entity.substr(2 if is_hex else 1)
		var valid := digits.is_valid_hex_number() if is_hex else digits.is_valid_int()
		if digits == "" or not valid:
			return ""
		var code := digits.hex_to_int() if is_hex else digits.to_int()
		# 0・サロゲート・範囲外は文字にしない
		if code <= 0 or code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF):
			return ""
		return String.chr(code)
	return NAMED_ENTITIES.get(entity, "")


## 出力を整える。改行の前の空白を除き、前後の空白・改行を落とす。
func _tidy(text: String) -> String:
	var tidy := RegEx.create_from_string(" +\\n").sub(text, "\n", true)
	return tidy.strip_edges()
