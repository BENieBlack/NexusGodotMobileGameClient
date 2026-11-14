## ダイヤの合計を求める純粋関数（client_design.md 4-2。F9 の例外）。
##
## 規則（これだけ）:
##   有償 = trx_diamond.paid_amount（null・{}・キー無し → 0）
##   無償 = trx_diamond.free_amount（暫定の項。キー無し → 0）
##        + trx_item_list の mst_item_id == "free_diamond" の行の free_amount の合計（削除行は除く）
##   合計 = 有償 + 無償
## trx_item の paid_amount は足さない（有償は trx_diamond だけ。同じ値を 2 経路で足さない）。
## 二重カウントしない理由: 無償の 2 つの置き場は、サーバーの書き込み経路が分かれていて同じ無償を
## 両方に載せない（初期付与は trx_item のみ・ボーナスは trx_diamond.free_amount のみ）。
## platform はここでは見ない（応答がすでに端末の platform の行だけ）。
class_name DiamondTotal
extends RefCounted


static func calculate(trx_diamond: Dictionary, trx_item_list: Array) -> int:
	var total := 0
	# trx_diamond が {}（行なし）なら get が 0 を返すので足されない。削除行は無いものとして扱う
	if not trx_diamond.is_empty() and not PlayerState.is_row_deleted(trx_diamond):
		total += PlayerState.to_int(trx_diamond.get("paid_amount", 0))
		total += PlayerState.to_int(trx_diamond.get("free_amount", 0))
	for row in trx_item_list:
		if not row is Dictionary:
			continue
		if str(row.get("mst_item_id", "")) != PlayerResourceIds.FREE_DIAMOND:
			continue
		if PlayerState.is_row_deleted(row):
			continue
		# 有償（paid_amount）は足さない
		total += PlayerState.to_int(row.get("free_amount", 0))
	return total
