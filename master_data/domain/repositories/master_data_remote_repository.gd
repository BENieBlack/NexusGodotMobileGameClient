## マスターの「サーバー側」を読む契約（version API と配信ファイル）。
##
## 目的: 同期 UseCase（CheckMasterDataUseCase）が通信の実装を知らずに、テストでは偽物に差し替えられるようにする。
## 実装: master_data/data/repositories/master_data_api_repository.gd。
## 失敗は例外にせず、結果型の error（AppError）で返す。
class_name MasterDataRemoteRepository
extends RefCounted


## version API を呼ぶ。deploy_id は端末が保存している sys_deploy_id（未取得なら 0）。
func fetch_version(_deploy_id: int) -> MasterVersionResult:
	push_error("未実装: MasterDataRemoteRepository.fetch_version")
	return null


## テーブル 1 つの SQLite ファイルを取得する。
func download_table(_table: MasterTable) -> MasterTableFileResult:
	push_error("未実装: MasterDataRemoteRepository.download_table")
	return null
