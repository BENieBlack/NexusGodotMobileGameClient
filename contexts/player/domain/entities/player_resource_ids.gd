## プレイヤーの所持データで使う識別子の定数（client_design.md 2-2・K8、overview U6）。
##
## 目的: ホームの表示で「コイン」「無償ダイヤ」「通常スタミナ」「回復間隔の設定キー」を見分ける文字列を
##       1 か所に集める。
## 注意（仮置き）: サーバーの `mst_item.id`（coin / free_diamond）・スタミナの type（normal）・
##       `MstConfigKey`（stamina_recovery_interval_seconds）と一致させる二重管理。サーバー側の定義を
##       変えたらここも直す（サーバー: NexusMobileGameServer-Laravel の mst_item シーダーと MstConfigKey）。
class_name PlayerResourceIds
extends RefCounted

## コインの mst_item.id（trx_wallet_list の mst_item_id）
const COIN := "coin"
## 無償ダイヤの mst_item.id（trx_item_list の mst_item_id）
const FREE_DIAMOND := "free_diamond"
## ホームのスタミナの横のアイコンに使う mst_item.id（スタミナ回復薬。stamina_50。client_design.md 5-5）。
## ホームは master_data を使わず固定の ID で絵を出すので、ここに持つ（サーバーの MstItemSeeder と一致させる二重管理）
const STAMINA_ICON_ITEM_ID := "stamina_50"
## ホームで使うスタミナの種類（trx_stamina_list の type。raid / pvp / event は使わない。P1）
const STAMINA_TYPE_NORMAL := "normal"
## スタミナの回復間隔（秒）を持つ mst_config の id
const STAMINA_RECOVERY_INTERVAL_KEY := "stamina_recovery_interval_seconds"
