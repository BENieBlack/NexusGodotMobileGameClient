## HtmlToBbcode（規約の HTML → BBCode）の単体テスト。純粋関数なので入力と出力の文字列だけを比べる。
extends GdUnitTestSuite


func _convert(html: String) -> String:
	return HtmlToBbcode.to_bbcode(html)


## 期待: h1〜h3 は大きさつきの太字。後ろの段落とは空行で区切られる。
func test_headings_are_sized_and_bold() -> void:
	assert_str(_convert("<h1>A</h1><h2>B</h2><h3>C</h3><p>x</p>")).is_equal(
		(
			"[font_size=44][b]A[/b][/font_size]\n\n"
			+ "[font_size=36][b]B[/b][/font_size]\n\n"
			+ "[font_size=32][b]C[/b][/font_size]\n\nx"
		)
	)


## 期待: 段落は空行で区切る。br は改行 1 つ。
func test_paragraph_and_br() -> void:
	assert_str(_convert("<p>one</p><p>two<br>three</p>")).is_equal("one\n\ntwo\nthree")


## 期待: ul は • 、ol は番号（入れ子は字下げ）。
func test_lists() -> void:
	assert_str(_convert("<ul><li>a</li><li>b<ul><li>c</li></ul></li></ul>")).is_equal(
		"• a\n• b\n    • c"
	)
	assert_str(_convert("<ol><li>a</li><li>b</li></ol>")).is_equal("1. a\n2. b")


## 期待: strong/b と em/i は同じ BBCode。大文字のタグ名も同じ。
func test_bold_and_italic() -> void:
	assert_str(_convert("<strong>a</strong><B>b</B><em>c</em><i>d</i>")).is_equal(
		"[b]a[/b][b]b[/b][i]c[/i][i]d[/i]"
	)


## 期待: http / https のリンクは [url]。href の &amp; はデコードされる。
func test_link_with_http_href() -> void:
	assert_str(_convert('<a href="https://e.com/?a=1&amp;b=2">go</a>')).is_equal(
		"[url=https://e.com/?a=1&b=2][color=#6db3ff]go[/color][/url]"
	)


## 期待: http / https 以外の href（javascript: など）や href 無しはリンクにせず、文字だけ残す。
func test_link_with_unsafe_href_keeps_text_only() -> void:
	assert_str(_convert('<a href="javascript:alert(1)">x</a>')).is_equal("x")
	assert_str(_convert("<a>y</a>")).is_equal("y")


## 期待: href の角括弧は符号化され、[url] を壊せない。
func test_link_href_brackets_are_encoded() -> void:
	var out := _convert('<a href="https://e.com/[x]">t</a>')
	assert_str(out).contains("https://e.com/%5Bx%5D")


## 期待: hr は区切り線の BBCode。前後は空行。
func test_hr() -> void:
	assert_str(_convert("<p>a</p><hr><p>b</p>")).is_equal("a\n\n[color=#777777][hr][/color]\n\nb")


## 期待: 名前つき・10 進・16 進のエンティティをデコードする。二重にはデコードしない。知らない名前は残す。
func test_entities_are_decoded_once() -> void:
	assert_str(_convert("&amp; &lt; &gt; &quot; &#169; &#x41;")).is_equal('& < > " © A')
	assert_str(_convert("&amp;lt;")).is_equal("&lt;")
	assert_str(_convert("&foo; &#xZZ;")).is_equal("&foo; &#xZZ;")
	# &nbsp; は U+00A0 になり、通常の空白のようにはまとめられない
	assert_str(_convert("a&nbsp;&nbsp;b")).is_equal("a  b")


## 期待: 本文の [ ] は BBCode として解釈されないよう [lb] [rb] になる（タグの注入を防ぐ）。
func test_brackets_in_text_are_escaped() -> void:
	assert_str(_convert("<p>[b]x[/b] [url=a]</p>")).is_equal("[lb]b[rb]x[lb]/b[rb] [lb]url=a[rb]")


## 期待: 未対応のタグ（span・table など）は捨て、中身の文字だけ残す。
func test_unsupported_tags_keep_inner_text() -> void:
	assert_str(_convert("<span class='x'>a</span><font color=red>b</font>")).is_equal("ab")


## 期待: script・style・head・title・コメント・DOCTYPE は中身ごと捨てる。閉じていない script は末尾まで捨てる。
func test_discarded_elements() -> void:
	var html := (
		"<!DOCTYPE html><html><head><title>T</title><style>p{color:red}</style></head>"
		+ "<body><!-- memo --><script>alert(1)</script><p>本文</p></body></html>"
	)
	assert_str(_convert(html)).is_equal("本文")
	assert_str(_convert("<p>a</p><script>alert(1)")).is_equal("a")


## 期待: 連続する空白・改行は 1 つにまとめ、行頭・行末の空白は捨てる。
func test_whitespace_is_normalized() -> void:
	assert_str(_convert("<p>  a \n\t b  </p>\n\n  <p> c </p>")).is_equal("a b\n\nc")


## 期待: タグの形でない "<" は本文として残る。属性値の ">" でタグが途切れない。
func test_lone_lt_and_gt_in_attribute() -> void:
	assert_str(_convert("1 < 2")).is_equal("1 < 2")
	assert_str(_convert('<a title="a>b" href="https://e.com">x</a>')).contains(
		"[url=https://e.com]"
	)


## 期待: 閉じ忘れ・入れ子の食い違いでも BBCode の開閉が揃う。対応しない閉じタグは無視する。
func test_unbalanced_tags_are_closed() -> void:
	assert_str(_convert("<b><i>x</b>y</i>z")).is_equal("[b][i]x[/i][/b]yz")
	assert_str(_convert("<b>x")).is_equal("[b]x[/b]")
	assert_str(_convert("a</b>b")).is_equal("ab")


## 期待: 空・空白だけの入力は空文字。
func test_empty_input() -> void:
	assert_str(_convert("")).is_equal("")
	assert_str(_convert("  \n ")).is_equal("")
