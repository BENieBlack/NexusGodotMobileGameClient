## JsonReader の単体テスト（D3: キー無しと null を同じに扱う）。
extends GdUnitTestSuite


## 前提: 配列の値・null・キー無しの 3 通りの辞書。操作: get_array。
## 期待: 配列はそのまま、null とキー無しは空配列。
## `.get(key, [])` だと null のとき null が返り、型付き変数への代入で型エラーになる事故を守る。
func test_get_array_treats_null_and_missing_alike() -> void:
	assert_array(JsonReader.get_array({"a": [1, 2]}, "a")).contains_exactly([1, 2])
	assert_array(JsonReader.get_array({"a": null}, "a")).is_empty()
	assert_array(JsonReader.get_array({}, "a")).is_empty()


## 前提: 配列のはずのキーに文字列が入っている。操作: get_array。期待: 空配列（警告は出るが落ちない）。
## サーバーの型が変わっても、画面が落ちずに空として扱えることを守る。
func test_get_array_returns_empty_on_wrong_type() -> void:
	assert_array(JsonReader.get_array({"a": "text"}, "a")).is_empty()


## 前提: 辞書の値・null・キー無し・型違い。操作: get_dict。
## 期待: 辞書はそのまま、他は空の辞書。
func test_get_dict_treats_null_missing_and_wrong_type_as_empty() -> void:
	assert_dict(JsonReader.get_dict({"d": {"k": 1}}, "d")).contains_key_value("k", 1)
	assert_dict(JsonReader.get_dict({"d": null}, "d")).is_empty()
	assert_dict(JsonReader.get_dict({}, "d")).is_empty()
	assert_dict(JsonReader.get_dict({"d": [1]}, "d")).is_empty()
