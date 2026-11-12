## GET /auth/version の応答を型付きにする（腐敗防止層。client_design.md 4・5 節、サーバー api.md 2 節）。
##
## 目的: 生の Dictionary を domain に渡さない。項目の欠落・null（D3）をここで吸収し、
##       needs_update が偽のときは needs_update と（あれば）maintenance だけという応答の揺れも受ける。
## 項目（サーバー api.md のまま）:
##   needs_update / sys_deploy_id / master.hash / master.tables（テーブル名 → {hash, url, file_size}）
## maintenance・asset は使わない（メンテの表示は 503 の本文で行う。client_design.md 8 節 5）。
class_name VersionResponse
extends RefCounted

var needs_update: bool = false
var sys_deploy_id: int = 0
var master_hash: String = ""
var tables: Dictionary = {}


## 応答の JSON（Dictionary）から作る。キー無し・null は既定値（偽・0・空）になる。
static func from_dict(data: Dictionary) -> VersionResponse:
	var response := VersionResponse.new()
	response.needs_update = bool(data.get("needs_update", false))
	response.sys_deploy_id = int(data.get("sys_deploy_id", 0))
	var master := JsonReader.get_dict(data, "master")
	response.master_hash = str(master.get("hash", ""))
	response.tables = JsonReader.get_dict(master, "tables")
	return response


## domain の MasterVersion に直す。tables の生の辞書は MasterTable の配列に変換する。
func to_domain() -> MasterVersion:
	var version := MasterVersion.new()
	version.needs_update = needs_update
	version.sys_deploy_id = sys_deploy_id
	version.master_hash = master_hash
	for table_name: String in tables:
		# テーブルの値が辞書でない（サーバー仕様の変化）ときは、その要素を無視して空の辞書として読む
		var info := JsonReader.get_dict(tables, table_name)
		version.tables.append(
			MasterTable.new(
				table_name,
				str(info.get("hash", "")),
				str(info.get("url", "")),
				int(info.get("file_size", 0))
			)
		)
	return version
