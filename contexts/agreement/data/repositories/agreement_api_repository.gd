## 規約 API の呼び出し（AgreementRepository の実装。client_design.md 3-1）。
##
## 目的: ApiClient の結果（ApiResult）を、domain が扱う結果型（AppError つき）に直す。
## 流れ:
##   fetch_pending: POST /agreement/pending → agreement_list（null と欠落は空。D3）を SysAgreement の配列にする。
##     応答が小さいので専用の *_response.gd は作らず、ここで取り出す。ボディは空の {}。list 系なので冪等キーは付けない
##   consent: POST /agreement/consent {sys_agreement_id} を冪等キーつきで送る。応答の本文（空の JSON）は使わない
## 失敗の扱い: ApiResult.to_app_error() で返す。24001・24002 の判断は UseCase（ここは業務の判断をしない）。
class_name AgreementApiRepository
extends AgreementRepository

var _api_client: ApiClient


func _init(api_client: ApiClient) -> void:
	_api_client = api_client


func fetch_pending() -> PendingAgreementsResult:
	var api_result := await _api_client.request("POST", "/agreement/pending")
	if not api_result.ok:
		return PendingAgreementsResult.new([], api_result.to_app_error())
	var agreements: Array[SysAgreement] = []
	for raw in JsonReader.get_array(api_result.data, "agreement_list"):
		if raw is Dictionary:
			agreements.append(
				SysAgreement.new(
					int(raw.get("sys_agreement_id", 0)),
					str(raw.get("version", "")),
					str(raw.get("title", "")),
					str(raw.get("url", "")),
					str(raw.get("published_at", ""))
				)
			)
	return PendingAgreementsResult.new(agreements)


func consent(sys_agreement_id: int, idempotency_key: String) -> Result:
	var api_result := await (
		_api_client
		. request(
			"POST",
			"/agreement/consent",
			{"sys_agreement_id": sys_agreement_id},
			# 成功応答の本文は空の配列 `[]`（サーバーは項目の無い成功をこう返す）。他の API では
			# 空本文を成功にしない（login などの取り違え防止）ので、consent だけ許可する
			{"idempotency_key": idempotency_key, "allow_empty_body": true}
		)
	)
	if not api_result.ok:
		return Result.failure(api_result.to_app_error())
	return Result.success()
