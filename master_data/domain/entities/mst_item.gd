## アイテムマスター（mst_item）の読み取りモデル（1 行 = 1 アイテム。名前は l10n で引いた値）。
##
## 目的: ログインボーナスなどで、アイテム ID から表示名を出すための値（client_design.md 5-1）。
## 項目:
##   deploy_key  配信の世代（mst_item の列）
##   id          アイテム ID（サーバーの mst_item.id。無償ダイヤは "free_diamond"）
##   type        アイテムの種別（currency など。mst_item.type）
##   is_wallet   wallet 系（コイン・ポイントなど）のアイテムか（mst_item.is_wallet。列が無い配信ファイルでは偽）
##   name        mst_item__l10n の name（言語は Repository が持つ）。l10n の行が無いときは空文字
## ルール・判断は持たない。名前が空のときの代替の文字は、使う側（login）が決める。
class_name MstItem
extends RefCounted

var deploy_key: int = 0
var id: String = ""
var type: String = ""
var is_wallet: bool = false
var name: String = ""
