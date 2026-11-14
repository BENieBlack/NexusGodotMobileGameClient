## 端末の時計から現在時刻を返す Clock の実装（client_design.md 2-2・3-3）。
##
## 実装: `Time.get_unix_time_from_system()`（UTC の UNIX 秒）。単調時計（Time.get_ticks_msec）は
##       モバイルのスリープ中に止まりうるので使わない（バックグラウンド中の経過が欠けるため。3-3）。
## skew_seconds: デバッグ専用のずれ。e2e の `--e2e-clock-skew` が「端末の時計がずれている」状況を
##       作るために設定する。製品では 0 のまま（誰も設定しない）。
class_name SystemClock
extends Clock

## 端末時計のずれ（秒）。正なら端末が進んでいる。既定 0（製品はこのまま）
var skew_seconds: int = 0


func now_unix() -> int:
	return int(Time.get_unix_time_from_system()) + skew_seconds
