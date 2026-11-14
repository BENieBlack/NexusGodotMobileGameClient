## ホームの表示値の束（client_design.md 2-2）。画面の文字列は持たない（文字列は presenter 側）。
class_name HomeSummary
extends RefCounted

## ログイン済みか（PlayerState が空でない）
var is_logged_in: bool = false
## プレイヤー名。null・未設定は空文字（「名前なし」にするのは presenter）
var player_name: String = ""
var player_id: String = ""
## レベル。無ければ -1
var level: int = -1
var coin: int = 0
var diamond_total: int = 0
var stamina_source: StaminaSource = StaminaSource.new()
