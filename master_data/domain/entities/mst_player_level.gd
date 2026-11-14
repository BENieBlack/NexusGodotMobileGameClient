## プレイヤーレベルマスター（mst_player_level）の読み取りモデル。
##
## サーバー状態の読み取りだけで、計算・判定は持たない（architecture.md 4 節）。
## スタミナの最大値はレベルから式で求めず、この max_stamina を読む（サーバーが正。Q3）。
class_name MstPlayerLevel
extends RefCounted

var deploy_key: int = 0
var level: int = 0
var required_exp: int = 0
var max_stamina: int = 0
