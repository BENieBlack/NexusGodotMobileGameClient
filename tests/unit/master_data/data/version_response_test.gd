## VersionResponse の単体テスト（version API の応答 → 型付き。D3: null と欠落を同じに扱う）。
extends GdUnitTestSuite


## 前提: サーバー api.md 2 節の needs_update: true の応答。操作: from_dict → to_domain。
## 期待: needs_update・sys_deploy_id・master.hash・tables が domain の MasterVersion に入る。
func test_parses_full_response() -> void:
	var response := (
		VersionResponse
		. from_dict(
			{
				"needs_update": true,
				"sys_deploy_id": 12,
				"master":
				{
					"hash": "abc",
					"tables":
					{"mst_item": {"hash": "t1", "url": "/masterdata/t1/a.sqlite", "file_size": 3}},
				},
			}
		)
	)
	var version := response.to_domain()
	assert_bool(version.needs_update).is_true()
	assert_int(version.sys_deploy_id).is_equal(12)
	assert_str(version.master_hash).is_equal("abc")
	assert_int(version.tables.size()).is_equal(1)
	var table := version.tables[0]
	assert_str(table.name).is_equal("mst_item")
	assert_str(table.hash).is_equal("t1")
	assert_str(table.url).is_equal("/masterdata/t1/a.sqlite")
	assert_int(table.file_size).is_equal(3)


## 前提: needs_update: false だけの応答 / master が null の応答。操作: from_dict。
## 期待: 例外にならず、既定値（偽・0・空）になる。サーバーは false のとき master を返さないため。
func test_missing_and_null_use_defaults() -> void:
	var only_flag := VersionResponse.from_dict({"needs_update": false})
	assert_bool(only_flag.needs_update).is_false()
	assert_dict(only_flag.tables).is_empty()
	var null_master := VersionResponse.from_dict({"needs_update": true, "master": null})
	assert_str(null_master.master_hash).is_empty()
	assert_dict(null_master.tables).is_empty()
	assert_array(null_master.to_domain().tables).is_empty()
