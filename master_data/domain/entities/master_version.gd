## version API の応答を domain の言葉にした値（client_design.md 5 節）。
##
## 目的: 同期 UseCase が「更新が要るか」「どのテーブルをどのハッシュで取るか」を判断するための入力。
##       API の JSON（data/api の VersionResponse）はこの型に直してから domain に渡る（腐敗防止層）。
## 項目:
##   needs_update   端末のマスターが古いか
##   sys_deploy_id  次回 deploy_version に送る値
##   master_hash    マスター全体のハッシュ（X-Master-Hash に使う）。master が無ければ空
##   tables         master.tables の各テーブル（MasterTable の配列。サーバーの並びのまま）
class_name MasterVersion
extends RefCounted

var needs_update: bool = false
var sys_deploy_id: int = 0
var master_hash: String = ""
var tables: Array[MasterTable] = []
