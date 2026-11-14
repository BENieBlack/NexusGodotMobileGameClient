## ダイヤの合計を求める純粋関数（client_design.md 4-2。F9 の例外）。
##
## 規則（これだけ）:
##   有償 = trx_diamond.paid_amount（null・{}・キー無し・削除行 → 0）
##   無償 = trx_item_list の mst_item_id == "free_diamond" の行の free_amount の合計（削除行は除く。行なし → 0）
##   合計 = 有償 + 無償
## 無償は trx_item の 1 行に集約された（free-diamond-item）。trx_diamond.free_amount は読まない:
## サーバーは応答から外したが、旧サーバー・誤配信でキーが来ても足さない（二重に数えない安全のため）。
## trx_item の paid_amount は足さない（有償は trx_diamond だけ）。
## platform はここでは見ない（応答がすでに端末の platform の行だけ）。
class_name DiamondTotal
extends RefCounted


static func calculate(trx_diamond: Dictionary, trx_item_list: Array) -> int:
	var total := 0
	# trx_diamond が {}（行なし）なら get が 0 を返すので足されない。削除行は無いものとして扱う
	if not trx_diamond.is_empty() and not PlayerState.is_row_deleted(trx_diamond):
		# free_amount はここでも読まない（上の規則）
		total += PlayerState.to_int(trx_diamond.get("paid_amount", 0))
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
