## ログインボーナス画面の表示モデル（GetLoginBonusScreenUseCase が作る。presenter は これだけを見る）。
##
## 項目:
##   use_text_fallback    カレンダーを出さず、今の文字の画面に落とすか（1-3）。真のときは normal・vip・receive_offer は無効
##   fallback_reason      落とす理由（NONE のとき落とさない）
##   normal / vip         段の表示値。段が無い（null）ときは出さない（T4）
##   show_received_notice 「本日のログインボーナスは受け取り済みです」を出すか（いずれかの段が今日の段で、
##                        どの段も is_granted_now が偽のときだけ。T3・U-3）。文字の画面では使わない
##   receive_offer        受け取りボタン（visible が真のときだけ出す）
##   rewards              「今日配られた報酬」の行（login_bonus_list の全行。受け取った順のまま）。
##                        FROM_LOGIN で非空のときだけ入り、FROM_HOME では常に空。文字の画面ではこれを文字にする
## 文字列は持たない（文言は presentation が決める）。
class_name LoginBonusScreen
extends RefCounted

enum FallbackReason {
	NONE,
	## 通常・VIP のどちらの段も無い（T4・旧サーバー。D4）
	NO_STAGE,
	## 進捗のある段が全てマスターを引けない（古いマスター。再取得しても引けない。2-4）。片方だけ引けるなら、その段だけ出す
	MASTER_UNAVAILABLE,
	## いずれかの段の周期の日数が 1 未満・8 超（C1）
	CYCLE_OUT_OF_RANGE,
}

var use_text_fallback: bool = false
var fallback_reason: FallbackReason = FallbackReason.NONE
var normal: CalendarStageView = null
var vip: CalendarStageView = null
var show_received_notice: bool = false
var receive_offer: ReceiveOffer = ReceiveOffer.new()
var rewards: Array[LoginBonusDisplay] = []
