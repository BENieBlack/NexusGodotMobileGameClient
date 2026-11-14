## 端末の現在時刻を返す契約（client_design.md 2-2・3-3、home-player-info）。
##
## 目的: 時刻に依存する処理（サーバー時刻のオフセットの算出、スタミナの回復表示）が
##       `Time` を直接呼ばず、この契約を通して現在時刻を得る。テストは偽の実装に差し替え、
##       時計に依存せずに期待値を固定できる。
## 実装: core/data/clock/system_clock.gd（端末の UTC の UNIX 秒。デバッグ用のずれを足せる）。
class_name Clock
extends RefCounted


## 端末の現在時刻（UTC の UNIX 秒）。サーバー時刻への補正（オフセット）は含まない。
func now_unix() -> int:
	push_error("未実装: Clock.now_unix")
	return 0
