## マスターの「端末側の保存」の契約（ハッシュ管理・ファイル保存・DB の切り替え）。
##
## 目的: 同期 UseCase が、ファイル・SQLite の実装を知らずに、テストでは偽物に差し替えられるようにする。
## 実装: master_data/data/repositories/local_master_data_repository.gd。
## MasterHashProvider を継承する理由: ApiClient が X-Master-Hash を付けるために master_hash() を
##   呼ぶ。マスターの持ち主（master_data）の Repository がそのまま供給元になれば、AppContext が
##   同じ 1 つのインスタンスを ApiClient にも渡せる（状態の持ち主が 1 つのまま）。
class_name MasterStorageRepository
extends MasterHashProvider


## 保存している sys_deploy_id（未取得なら 0）。version API の deploy_version に使う。
func deploy_id() -> int:
	push_error("未実装: MasterStorageRepository.deploy_id")
	return 0


## 保存しているテーブルごとのハッシュ（テーブル名 → ハッシュ）。差分の判定に使う。
func table_hashes() -> Dictionary:
	push_error("未実装: MasterStorageRepository.table_hashes")
	return {}


## そのテーブル・ハッシュのファイルが端末に実在するか。ハッシュが保存済みと同じでも、
## ファイルが消えていれば取り直すための判定に使う（差分は「ハッシュが違う、またはファイルが無い」）。
func has_table_file(_table_name: String, _hash: String) -> bool:
	push_error("未実装: MasterStorageRepository.has_table_file")
	return false


## ダウンロードしたテーブルのファイルを保存する（まだ使い始めない。commit_update で切り替える）。
## 戻り値: 書き込みに成功したら true。
func save_table_file(_table_name: String, _hash: String, _bytes: PackedByteArray) -> bool:
	push_error("未実装: MasterStorageRepository.save_table_file")
	return false


## 更新を確定する: 保存したファイルを開き直して DB を切り替え、成功したらハッシュと deploy_id を保存する。
## 必須のテーブルが揃わないときは同梱 DB に戻し、何も保存せずに false を返す。
## 全テーブルの取得が終わってから 1 回だけ呼ぶ（途中で失敗したら旧 DB のまま。client_design.md 5 節）。
func commit_update(_version: MasterVersion) -> bool:
	push_error("未実装: MasterStorageRepository.commit_update")
	return false
