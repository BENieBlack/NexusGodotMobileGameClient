## 画面を出す前に、段の ID をマスターから引いておく UseCase（古いマスターへの備え。client_design.md 2-4）。
##
## 目的: 応答の段の ID が新しい（サーバーがマスターを更新した直後）・ダウンロードが失敗していた・同梱 DB
##       しか無い、といったときに、端末のマスターで ID を引けない。そのとき 1 回だけマスターを取り直す。
## 流れ（handle。呼び出し側は await する）:
##   1. メモリの進捗の段の ID をマスターで引く（LoginBonusStageMasterReader）
##   2. 全部引けたら終わり（再取得しない）
##   3. 引けない段があれば、CheckMasterDataUseCase.handle() を **1 回だけ**実行する
##      （「行が無い」も「読めない」＝古い配信ファイルで列が無いも、同じ再取得の対象）
##   4. 結果が UPDATED のときだけ引き直す。UP_TO_DATE（変わらない）・FAILED・IN_PROGRESS（ほかで同期中）は
##      引き直さず、その段は引けないまま返す。ループはしない
## 結果（PrepareLoginBonusMasterResult）: masters（引けた段だけ非 null）と covers（全部引けたか）。
##   covers が偽のとき、画面（GetLoginBonusScreenUseCase）は画面全体を文字の画面にする（1-3 ④）。
## 失敗の扱い: 例外にしない。ここでは「引けなかった」を結果で返すだけ。
class_name PrepareLoginBonusMasterUseCase
extends RefCounted

var _reader: LoginBonusStageMasterReader
var _check_master_data: CheckMasterDataUseCase


func _init(reader: LoginBonusStageMasterReader, check_master_data: CheckMasterDataUseCase) -> void:
	_reader = reader
	_check_master_data = check_master_data


func handle(calendars: LoginBonusCalendars) -> PrepareLoginBonusMasterResult:
	# --- 1・2. 引く。全部引けたら終わり ---
	var masters := _reader.read(calendars)
	if masters.covers(calendars):
		return PrepareLoginBonusMasterResult.new(masters, true)

	# --- 3. 古いマスター。1 回だけ取り直す ---
	var check := await _check_master_data.handle()
	# --- 4. 更新があったときだけ引き直す ---
	if check.status == CheckMasterDataResult.Status.UPDATED:
		masters = _reader.read(calendars)
	return PrepareLoginBonusMasterResult.new(masters, masters.covers(calendars), true, check.status)
