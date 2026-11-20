## NumberText（桁区切り）のテスト。HomeText.format_number と同じ結果になること（共通化の前後で表示が変わらない）を含む。
extends GdUnitTestSuite


## 前提: 桁の境界（0・3 桁・4 桁・5 桁・100 万）と負数。期待: 3 桁ごとにカンマ。
func test_format_number_cases() -> void:
	var cases := {
		0: "0",
		5: "5",
		999: "999",
		1000: "1,000",
		20000: "20,000",
		123456: "123,456",
		1000000: "1,000,000",
		-1: "-1",
		-999: "-999",
		-1000: "-1,000",
		-1234567: "-1,234,567",
	}
	for value: int in cases:
		assert_str(NumberText.format_number(value)).is_equal(cases[value])


## 前提: 同じ値。期待: HomeText.format_number と NumberText が同じ結果（ホームの表示が従来と変わらない）。
func test_same_as_home_text() -> void:
	for value in [0, 7, 999, 1000, 20000, 65535, -42, -12345]:
		assert_str(NumberText.format_number(value)).is_equal(HomeText.format_number(value))
