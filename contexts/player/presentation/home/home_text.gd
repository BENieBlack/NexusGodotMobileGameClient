## ホームに出す文字列を作る小さなヘルパー（client_design.md 1-3）。
##
## 目的: 表示の文言・桁区切り・時間の書式を presenter から分け、単体テストしやすくする。
##       値の決定は domain（HomeSummary・StaminaDisplay）で済んでいて、ここは文字列にするだけ。
class_name HomeText
extends RefCounted

const NOT_LOGGED_IN := "ログインしていません"
const NO_NAME := "名前なし"
## 値が無いときの表示
const DASH := "-"


## 整数を 3 桁区切りにする（1000 → "1,000"。負数も扱う）。
static func format_number(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	var count := 0
	# 後ろから 3 桁ごとに区切りを入れる
	for i in range(digits.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = "," + out
		out = digits[i] + out
		count += 1
	return ("-" if value < 0 else "") + out


## 名前の位置の文字列。未ログインは「ログインしていません」、名前が空なら「名前なし」。
static func name_text(summary: HomeSummary) -> String:
	if not summary.is_logged_in:
		return NOT_LOGGED_IN
	return summary.player_name if summary.player_name != "" else NO_NAME


static func id_text(summary: HomeSummary) -> String:
	if not summary.is_logged_in:
		return DASH
	return "ID: " + summary.player_id


## レベル。未ログインは「-」、level が無ければ「Lv.-」。
static func level_text(summary: HomeSummary) -> String:
	if not summary.is_logged_in:
		return DASH
	if summary.level < 0:
		return "Lv.-"
	return "Lv.%d" % summary.level


static func coin_text(summary: HomeSummary) -> String:
	if not summary.is_logged_in:
		return DASH
	return format_number(summary.coin)


static func diamond_text(summary: HomeSummary) -> String:
	if not summary.is_logged_in:
		return DASH
	return format_number(summary.diamond_total)


## スタミナの「現在値 / 最大値」。未ログイン・行なしは「-」、最大値が不明なら「42 / --」。
static func stamina_text(summary: HomeSummary, display: StaminaDisplay) -> String:
	if not summary.is_logged_in or not display.is_present:
		return DASH
	if display.max_stamina < 0:
		return "%d / --" % display.current
	return "%d / %d" % [display.current, display.max_stamina]


## 残り時間の行。出さないとき（seconds_to_next が負）は空文字（行は残して高さを保つ）。
static func remain_text(display: StaminaDisplay) -> String:
	if display.seconds_to_next < 0:
		return ""
	return "次の回復まで " + format_duration(display.seconds_to_next)


## 秒を mm:ss にする。1 時間以上は h:mm:ss。
static func format_duration(seconds: int) -> String:
	var total := maxi(0, seconds)
	@warning_ignore("integer_division")
	var hours := total / 3600
	@warning_ignore("integer_division")
	var minutes := (total % 3600) / 60
	var secs := total % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, secs]
	return "%02d:%02d" % [minutes, secs]
