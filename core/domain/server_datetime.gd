## サーバーの時刻文字列 `Y-m-d H:i:s`（UTC。印は付かない。api.md 3.2）を UNIX 秒に読む純粋関数。
##
## 目的: Godot の `Time.get_unix_time_from_datetime_string()` は、解釈できない文字列に例外ではなく
##       0 を返す（1970-01-01 と区別できない。client_design.md 0-e）。そのため、先に書式と値の範囲を
##       検査し、読めないときは 0 ではなく -1（失敗）を返す。
## 使う場所: スタミナの `last_recovery_at` など、サーバーの時刻文字列を読む箇所。
class_name ServerDatetime
extends RefCounted

## 読めなかったことを表す値（有効な時刻は 1970 年以降の 0 以上なので衝突しない）
const INVALID := -1

static var _pattern: RegEx = null


## text（例 "2026-11-14 02:03:19"）を UTC の UNIX 秒にする。書式・範囲が不正なら INVALID（-1）。
static func parse_to_unix(text: String) -> int:
	if _pattern == null:
		_pattern = RegEx.new()
		_pattern.compile("^(\\d{4})-(\\d{2})-(\\d{2}) (\\d{2}):(\\d{2}):(\\d{2})$")
	var matched := _pattern.search(text)
	if matched == null:
		return INVALID
	var year := int(matched.get_string(1))
	var month := int(matched.get_string(2))
	var day := int(matched.get_string(3))
	var hour := int(matched.get_string(4))
	var minute := int(matched.get_string(5))
	var second := int(matched.get_string(6))
	# 書式は合っていても 13 月・25 時などは Godot が黙って丸めるので、範囲を先に弾く
	if year < 1970 or month < 1 or month > 12 or day < 1 or day > 31:
		return INVALID
	if hour > 23 or minute > 59 or second > 59:
		return INVALID
	# 存在しない日（2 月 30 日など）は Godot がエラーを出すので、変換の前に月ごとの日数で弾く
	if day > _days_in_month(year, month):
		return INVALID
	return Time.get_unix_time_from_datetime_dict(
		{"year": year, "month": month, "day": day, "hour": hour, "minute": minute, "second": second}
	)


## year 年 month 月の日数（うるう年を考慮）。
static func _days_in_month(year: int, month: int) -> int:
	if month == 2:
		var is_leap := (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
		return 29 if is_leap else 28
	if month in [4, 6, 9, 11]:
		return 30
	return 31
