## ユニットマスター（mst_unit）の読み取りモデル。
##
## サーバー状態の読み取りだけで、計算・判定は持たない（architecture.md 4 節。ビジネスルールは各コンテキスト）。
## type / element / rarity は DB の文字列のまま持つ（"Attack" / "Fire" / "SSR" など）。
## 名前: 旧 scripts/models/mst/mst_unit.gd の class_name MstUnit と衝突するため、旧構成が残る間は
##       MasterUnit としている。旧の削除（第 2 段）後に MstUnit へ改名してよい（引き継ぎ事項）。
## 多言語名（l10n）は旧実装でも未対応（id を名前代わりにしていた）なので持たない。
class_name MasterUnit
extends RefCounted

var id: String = ""
var deploy_key: int = 0
var type: String = ""
var element: String = ""
var rarity: String = ""
