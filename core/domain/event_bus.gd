## 起きたことを伝えるだけのシグナルの置き場（オートロード EventBus。architecture.md 3 節）。
##
## 目的: コンテキスト・master_data が互いを参照せずに通知し合う（サーバーの Dispatcher に相当）。
## 注意:
##   - class_name を付けない。オートロード名と同じ class_name は Godot 4 で
##     "Class hides an autoload singleton" になる（依存チェック L1）。
##   - project.godot の [autoload] に登録済み（依存チェック D2 は、登録されたオートロードだけ Node 継承を
##     許すため、core/domain に置くこのファイルは登録が要る）。AppContext の登録と、受け手の接続は第 2 段。
##   - シグナルを出すのは AppContext だけ（ApiClient のシグナルを中継する。core/data は
##     オートロード名を参照できないため。依存チェック A1）。受け手の登録も AppContext。
extends Node

## refresh に失敗してセッションを破棄したとき。受け手: auth（トークン）・player・login。
## master_data は受けない（マスターは端末のもので、アカウントに依存しない）
@warning_ignore("unused_signal")
signal session_expired

## 起動後にサーバーのマスターが更新されたとき（X-Master-Update-Required）。受け手: master_data だけ
@warning_ignore("unused_signal")
signal master_update_required
