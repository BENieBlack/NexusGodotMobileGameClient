## HTTP の `Date` ヘッダー（RFC 7231 の IMF-fixdate。例 `Sat, 14 Nov 2026 02:41:23 GMT`）を
## UNIX 秒に読む純粋関数（client_design.md 2-2・3-3）。
##
## 目的: login 応答の Date からサーバー時刻とのオフセットを作る。読めない値は例外にせず -1 を返し、
##       呼び出し側が「端末時計のみ」に切り替える。
class_name HttpDate
extends RefCounted

const INVALID := -1
const MONTHS: Array[String] = [
	"jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"
]

static var _pattern: RegEx = null


## text を UTC の UNIX 秒にする。書式・範囲が不正なら INVALID（-1）。
## 曜日は読まない（日付から決まるので検証しても得がない）。
static func parse_to_unix(text: String) -> int:
	if _pattern == null:
		_pattern = RegEx.new()
		_pattern.compile(
			"^[A-Za-z]{3}, (\\d{2}) ([A-Za-z]{3}) (\\d{4}) (\\d{2}):(\\d{2}):(\\d{2}) GMT$"
		)
	var matched := _pattern.search(text.strip_edges())
	if matched == null:
		return INVALID
	var month := MONTHS.find(matched.get_string(2).to_lower()) + 1
	if month == 0:
		return INVALID
	# 月名以外は Y-m-d H:i:s と同じ検査に任せる（範囲・存在しない日の丸めの検出を 1 か所に保つ）
	var normalized := (
		"%s-%02d-%s %s:%s:%s"
		% [
			matched.get_string(3),
			month,
			matched.get_string(1),
			matched.get_string(4),
			matched.get_string(5),
			matched.get_string(6),
		]
	)
	return ServerDatetime.parse_to_unix(normalized)
