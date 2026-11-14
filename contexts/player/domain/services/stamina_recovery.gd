## スタミナの自然回復の表示値を求める純粋関数（client_design.md 3-1。F9 の例外）。
##
## 目的: login 応答の current_stamina / last_recovery_at を起点に、now 時点の表示値を求める。
##       サーバーの式（floor(経過秒 × 倍率 ÷ 間隔)・最大値で進めない・last_recovery_at は点数分だけ進める）と
##       同じ値を、整数だけで計算する（浮動小数の誤差で 1 点ずれないよう、倍率は 100 倍の整数）。
## 二重加算しない理由: 起点（StaminaSource）は不変で、毎回その起点から now までを計算し、結果を書き戻さない。
##       tick を何度繰り返しても、画面を開き直しても同じ値になる。
## 状態を持たず now を引数で受けるので、単体テストは時計に依存しない。
class_name StaminaRecovery
extends RefCounted


static func calculate(source: StaminaSource, now_unix: int) -> StaminaDisplay:
	# --- 1. 回復を計算できない条件（現在値は起点のまま、残り時間なし） ---
	if (
		not source.is_present
		or source.max_stamina < 0
		or source.interval_seconds <= 0
		or source.rate_x100 <= 0
		or source.recovered_at_unix < 0
	):
		return StaminaDisplay.new(source.current, source.max_stamina, -1, source.is_present)

	# --- 2. 最大値以上なら回復しない（経過時間の計算より先）---
	# サーバーは最大値のとき last_recovery_at を進めず、経過が大きいまま残る。先に判定しないと、
	# 存在しない回復を足してしまう。最大値超過（レベルアップ時の加算）も丸めずそのまま出す（Q11）
	if source.current >= source.max_stamina:
		return StaminaDisplay.new(source.current, source.max_stamina, -1, true)

	# --- 3. 経過秒。端末時計が過去へずれても負にしない ---
	var elapsed := maxi(0, now_unix - source.recovered_at_unix)

	# --- 4. 回復した点数（整数の切り捨て。サーバーの floor と同じ） ---
	@warning_ignore("integer_division")
	var points := elapsed * source.rate_x100 / (source.interval_seconds * 100)

	# --- 5. 最大値で止める ---
	var current := mini(source.current + points, source.max_stamina)

	# --- 6. 残り時間。最大値に達したら消す ---
	if current >= source.max_stamina:
		return StaminaDisplay.new(current, source.max_stamina, -1, true)
	# 次の 1 点が入る時刻 = ceil((points + 1) × 間隔 × 100 ÷ 倍率)（整数の切り上げ）。経過との差は必ず 1 以上
	# 注意: サーバーの calcTimeUntilNextRecovery は ceil((間隔 - (int(経過×倍率) % 間隔)) / 倍率) で、倍率が 1 でないと
	# 小数部の切り捨ての違いで最大 1 秒ずれる（例: 間隔 300・倍率 1.5・経過 199 秒でサーバー 2、ここは 1）。
	# 表示専用の値で、回復の点数（上の points）はサーバーと全経過秒で一致する。残り時間は厳密には合わせない（人が許容する範囲の差）
	var numerator := (points + 1) * source.interval_seconds * 100
	@warning_ignore("integer_division")
	var next_at := (numerator + source.rate_x100 - 1) / source.rate_x100
	return StaminaDisplay.new(current, source.max_stamina, next_at - elapsed, true)
