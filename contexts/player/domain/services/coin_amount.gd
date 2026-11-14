## コインの所持数を求める純粋関数（client_design.md 4-1。Q13）。
##
## trx_wallet_list の mst_item_id が "coin" の行の free_amount。paid_amount は足さない・gold など
## 他の行は見ない。削除行は無いものとして扱い、行が無ければ 0（残高なしは行が無い。api.md 2.4）。
class_name CoinAmount
extends RefCounted


static func calculate(trx_wallet_list: Array) -> int:
	var total := 0
	for row in trx_wallet_list:
		if not row is Dictionary:
			continue
		if str(row.get("mst_item_id", "")) != PlayerResourceIds.COIN:
			continue
		if PlayerState.is_row_deleted(row):
			continue
		total += PlayerState.to_int(row.get("free_amount", 0))
	return total
