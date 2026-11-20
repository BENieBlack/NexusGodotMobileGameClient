## 数値を表示用の文字列にする小さなヘルパー（client_design.md 1-2。ログインボーナスとホームで共用）。
##
## 目的: 桁区切りの規則を 1 か所に置く（HomeText.format_number と同じ結果）。
class_name NumberText
extends RefCounted


## 整数を 3 桁区切りにする（20000 → "20,000"、-1234 → "-1,234"、0 → "0"）。
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
