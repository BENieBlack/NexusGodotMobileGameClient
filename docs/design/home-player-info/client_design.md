# ホーム＋プレイヤー情報 クライアント設計

- 要件: `Nexus/docs/requirements/home-player-info.md`
- 全体設計: `Nexus/docs/design/home-player-info/overview.md`（決定 Q1〜Q5・Q10〜Q13・D1〜D3、仮置き P1〜P6・U3・U5・U6、未解決 U2・U7）
- サーバー設計（正）: `NexusMobileGameServer-Laravel/docs/design/home-player-info/{db,api,sequence}.md`（login の応答項目は api.md 2 節、X-Platform は 10 節、MstConfig の配信は 6 節、サインアップ時の初期付与は 4 節）
- 前提: [title-to-home のクライアント設計](../title-to-home/client_design.md)（`ApiClient`・login・`master_data` の仕組み。ここには複製せず、差分だけ書く）
- 決定: `Nexus/docs/adr/0002-client-clean-architecture-ddd-lite.md`（3 層・master_data 共有モジュール）

> 改訂（2026-11-14、人の指示）: login 応答のダイヤ（有償）は `trx_diamond_list`（一覧）ではなく **`trx_diamond`（X-Platform の platform の 1 行のオブジェクト）**。行が無いときは `null`（サーバー設計の更新 PR に従う。仮置き）。このため「端末の platform の行を選ぶ処理」と「全行の合計」は無く、platform はダイヤの行の選択には使わない（`X-Platform` ヘッダー用にだけ決める）。

## 0. 現状の確認結果（設計の前提）

| # | 確認したこと | 場所 |
| --- | --- | --- |
| a | ホームはプレイヤー ID だけを出す（`HomePresenter` は `GetPlayerIdUseCase` だけを使う）。`home.tscn` は `CenterContainer` の中央寄せのパネル 1 つ（幅 800）。名前・レベル・スタミナ・通貨は保持のみで出していない | `contexts/player/presentation/home/` |
| b | `PlayerState` は `sys_player`（辞書）と `trx_lists`（6 種。`trx_diamond_list` を含む）を辞書のまま持つ。`ApplyLoginDataUseCase` が 6 種を空配列で補って置き換える。`LoginResponse` は `JsonReader` で null・欠落を `[]` / `{}` にする | `player/domain/`、`login/data/api/login_response.gd` |
| c | `ApiClient` は `_build_headers()` で `Authorization`・`X-Master-Hash`・`X-Unique-Request-Identifier` だけを付ける。`X-Platform` は無い。OS の判定は `auth_api_repository.gd` が `OS.get_name()` を device_info に使うだけ | `core/data/http/api_client.gd` |
| d | **U3 の答え（実行で確認）**: 成功応答の `ApiResult.headers` は `"Name: value"` の配列として保持され、`Date` ヘッダーも失われない（`_classify` → `make_ok(status, data, headers)`）。開発サーバー（nginx）の `GET /auth/version` は `Date: Sat, 14 Nov 2026 02:41:23 GMT` を返す（`curl -I`。読み取りのみ）。login（POST）の応答でも同じ nginx が付ける見込みだが、login 自体の実測は S5 で確かめる（確認手順 8-3 のケース 2）。**サーバー変更は要らない** | 実行（curl）、`api_client.gd:_classify` |
| e | Godot の `Time.get_unix_time_from_datetime_string("2026-11-14 02:03:19")` は空白区切りの `Y-m-d H:i:s` を解釈し、UTC の UNIX 秒（1794621799）を返す（Godot 4.7.2 で実行して確認）。**解釈できない文字列は 0 を返す**（例外にならない）ので、書式を先に検査する | 実行（headless スクリプト） |
| f | `master_data` の `MasterDatabase.REQUIRED_TABLES` は `mst_gacha` / `mst_unit` / `mst_equipment` の 3 つ。同梱 `data/master.db` も同じ 3 テーブル（と `__l10n`）だけで、`mst_player_level`・`mst_config` は無い。更新 DB は version の `tables` をすべて開くので、配信に両方があれば追加の実装なしで同じ接続の仕組みに載る。`select_rows` は、テーブルを持つ DB が無いとき空配列を返す | `master_data/data/local/master_database.gd` |
| g | `Toast`（Reverb）の `/broadcasting/auth` は `ApiClient` を通らず、サーバーの `maintenance` グループ外（X-Platform 不要）。規約の本文取得と配信ファイルの取得は `ApiClient.download()`（`_send_http` を直接呼ぶ。API のホストではないものを含む） | `core/presentation/toast.gd`、`api_client.gd:download` |
| h | e2e ドライバーはホームに入って 2 秒（+ `--e2e-dwell`）で終了し、`E2E_RESULT: OK player_id=...` だけを出す。ホームの値は検証していない | `debug/e2e_driver.gd` |

## 1. 画面・シーン構成と遷移

### 1-1. 遷移

遷移は変えない（タイトル → 規約 → ログインボーナス → ホーム。title-to-home 1-1）。ホームは `SceneRouter.goto_home()` で開き、**開くたびに通信しない**（Q2。login の値とローカルのマスターだけで描く）。導線ボタン（メール・お知らせ）は枠だけで、押しても何も起きない（P3）。

### 1-2. シーン構成（縦長 1080x1920。`project.godot` の `window/size` と一致）

`home.tscn` を作り直す（ルートの `Control` に `HomePresenter` を付けるのは今と同じ。`BgVideo` も残す）。中央寄せの小さなパネルをやめ、**上から「プレイヤー」「スタミナ」「通貨」、下に導線**の縦並びにする。見た目の作り込み（アイコン・演出）は対象外なので、既存の `casual_theme.tres` とラベル・`PanelContainer` だけで組む。

```
Home (Control, HomePresenter)
├─ BgVideo (VideoStreamPlayer)                      背景（今のまま）
├─ StaminaTimer (Timer, 1.0 秒, one_shot=false)     スタミナ表示の更新（3-4）
└─ Margin (MarginContainer)                         全面。左右 48px、上下は 96px + 端末のセーフエリア
   └─ Root (VBoxContainer, separation 32)
      ├─ PlayerPanel (PanelContainer)               プレイヤー
      │  └─ VBox
      │     ├─ NameLabel          font 56   「名前なし」を含む
      │     └─ Row (HBox)
      │        ├─ IdLabel         font 36   「ID: ABCD1234」（左、expand）
      │        └─ LevelLabel      font 48   「Lv.12」（右）
      ├─ StaminaPanel (PanelContainer)              スタミナ
      │  └─ VBox
      │     ├─ StaminaTitle       font 36   「スタミナ」
      │     ├─ StaminaValueLabel  font 72   「42 / 50」
      │     └─ StaminaRemainLabel font 36   「次の回復まで 04:32」。高さを固定（隠しても詰めない）
      ├─ CurrencyRow (HBoxContainer, 等幅 2 つ)     通貨
      │  ├─ CoinPanel     └ CoinTitle「コイン」(36) / CoinValueLabel(56)
      │  └─ DiamondPanel  └ DiamondTitle「ダイヤ」(36) / DiamondValueLabel(56)
      ├─ Spacer (Control, size_flags_vertical = EXPAND)  余白（将来のメイン領域）
      └─ NavRow (HBoxContainer, 等幅 2 つ, 各ボタン 高さ 160 以上)
         ├─ MailButton (Button「メール」)   └ MailBadge (PanelContainer 56x56, 右上に重ねる。数字なし)
         └─ NoticeButton (Button「お知らせ」) └ NoticeBadge (同上)
```

- 数値・ID・名前は 1080 幅でも折り返さず、はみ出すときは**フォントを下げずに省略記号で省略（`text_overrun_behavior = TRIM_ELLIPSIS`）**にする（名前は 8 文字想定、ダイヤは 9 桁の桁区切り付きまで確認手順 9 で見る）。
- タッチ対象のボタンは高さ 160 以上（親指で押せる大きさ）。下端は端末のセーフエリア（ホームバー）を避ける。セーフエリアは `DisplayServer.get_display_safe_area()`（**物理ピクセルの `Rect2i`**）から presenter が `Margin` のオフセットに反映する。`project.godot` は 1080x1920・`stretch/mode=canvas_items` で、レイアウトの値はビューポート座標なので、**ウィンドウサイズ（`DisplayServer.window_get_size()`）に対するビューポートサイズ（`get_viewport().get_visible_rect().size`）の比**で物理ピクセルからビューポート座標へ変換してから余白に足す（上の余白 = 変換した `safe.position.y`、下の余白 = 変換した `window.y − safe.end.y`。そのまま足すと余白が実際の何倍にもずれる）。変換は presenter ではなく純粋関数（`SafeAreaMargins.to_viewport(safe, window_size, viewport_size)` のような小さなヘルパー）にして単体テストする。エディタ・デスクトップでは安全領域が全面と同じで余白は 0。値は仮置きで、実機・シミュレーターで調整する（9 節 E6）。
- 未読バッジ（Q10）: 数字は出さない。**輪郭だけの小さな円**を右上に置く（バッジの位置と大きさを決めるための枠）。後続の機能が数字を入れるときは `MailBadge` の中に `Label` を足す。
- ボタンの押下は何もしない（P3。`pressed` を接続しない。押下の見た目はテーマのまま）。

### 1-3. 項目ごとの表示と状態

表示の文字列を作るのは presenter（`HomeText` のような `presentation` の小さなヘルパーに分けてよい。単体テストしやすくする）。値の決定は domain（2 節）。

| 項目 | 通常 | 欠けているとき |
| --- | --- | --- |
| 名前 | `sys_player.name` | null・空文字 → **「名前なし」**（Q7） |
| ID | 「ID: ＋ `my_id`」 | 未ログイン → 「ログインしていません」を名前の位置に出し、ID・レベル・スタミナ・通貨は「-」（この画面にログイン前に来るのは直接起動の検証だけ。D4 により通常の経路では起きない） |
| レベル | 「Lv.＋整数」 | `level` が無い → 「Lv.-」 |
| スタミナ | 「現在値 / 最大値」。最大値未満のとき「次の回復までは mm:ss」（1 時間以上は h:mm:ss）。最大値のときは残り時間を消す（行は残して高さを保つ） | 下の表 |
| コイン | `trx_wallet_list` の `mst_item_id` が `coin` の行の `free_amount`（Q13。`gold` は出さない）。桁区切りあり（「1,000」。仮置き） | **行が無い → 0**（api.md 2.4。残高なしは行が無い） |
| ダイヤ | **有償 + 無償の合計**（4 節）。桁区切りあり | `trx_diamond` が null・欠落 → 有償 0・暫定の無償 0。`free_diamond` の行が無い → 0 |
| 導線 | メール・お知らせのボタンとバッジの枠 | - |

**スタミナの状態**（P1: `trx_stamina_list` の `type` が `normal` の行だけを使う。`raid` / `pvp` / `event` は無視）:

| 状態 | 条件 | 現在値 / 最大値 | 残り時間 | 回復の計算 |
| --- | --- | --- | --- | --- |
| スタミナ行なし | `normal` の行が無い（既存プレイヤー。Q9・Q18） | 「-」 | なし | しない |
| 読み込み前 | 未ログイン（`PlayerState` が空） | 「-」 | なし | しない |
| 通常 | 最大値・回復間隔・倍率が使える | 計算した現在値 / 最大値 | あり（最大値未満） | する |
| 最大値 | 現在値 >= 最大値 | 「50 / 50」 | なし | しない（3 節。最大値判定が先） |
| **最大値超過** | 現在値 > 最大値（レベルアップ時の加算。Q11） | **丸めず「55 / 50」** | なし | しない |
| **最大値が分からない**（U2） | `mst_player_level` が読めない（配信なし・更新失敗・該当レベルの行なし。最大レベル 100 超を含む） | 「42 / --」（現在値だけ。login 時点の値のまま） | なし | **しない**（最大値で止められないため。起点の現在値を勝手に増やさない） |
| **回復間隔が分からない**（P5） | `mst_config` に `stamina_recovery_interval_seconds` が無い・整数でない・1 未満 | 「現在値 / 最大値」（login 時点の値のまま） | なし | しない |
| 起点が読めない | `last_recovery_at` が `Y-m-d H:i:s` でない・`recovery_rate_multiplier` が数値でない・0 以下 | 「現在値 / 最大値」（login 時点の値のまま） | なし | しない |

通信の失敗・読み込み中の表示は発生しない（ホームは通信しない）。読み込み前は未ログインだけ。

## 2. 構成と変更するファイル

構成の方針は `.claude/architecture.md`。内部設計は層の分担と責務まで書き、細部は S5 で決める。

### 2-1. 層の分担（要点）

| 層 | 責務 |
| --- | --- |
| presentation（`player/presentation/home/`） | `HomePresenter` が UseCase 2 つを呼び、ラベルへ反映する。`StaminaTimer`（1 秒）の tick と復帰通知で `GetStaminaDisplayUseCase` を呼び直す。`master_data_loaded`（マスター更新）で `GetHomeSummaryUseCase` を呼び直す。計算・判定はしない |
| domain（`player/domain/`） | 表示用の値（`HomeSummary`・`StaminaSource`・`StaminaDisplay`）、**回復の純粋関数**（`StaminaRecovery`）、ダイヤ合計の純粋関数（`DiamondTotal`。ともに `domain/services/`。K9）、UseCase 2 つ。`Node`・`HTTPRequest`・`FileAccess` に依存しない |
| domain（`master_data/domain/`） | `MstPlayerLevel`・`MstConfig` の読み取りモデルと Repository の契約。**読み取りのみ**（ルール・計算は置かない） |
| data | `master_data/data/` に SQLite の実装。`player/data/` は変更なし（メモリ保持）。`login/data/` が login 応答から `trx_diamond` とサーバー時刻のオフセットを取り出す。`core/data/` が `X-Platform` の付与と `Date` の解釈 |

F9（クライアントは独自の計算を足さない）の例外は 2 つだけ: **スタミナの自然回復の表示**（H5・Q4・Q5）と**ダイヤの合算**（D3）。どちらも表示専用で、結果をサーバーへ送らず、保持データも書き換えない。

### 2-2. 追加・変更するファイル

| 区分 | 場所 | 内容 |
| --- | --- | --- |
| 追加 | `master_data/domain/entities/mst_player_level.gd`、`mst_config.gd` | 読み取りモデル。`MstPlayerLevel`: `level`・`required_exp`・`max_stamina`（整数）。`MstConfig`: `id`・`value`（文字列のまま）・`value_type`、`value_as_int() -> int`（`value_type` が `int` で整数に読めるときだけその値、他は -1。**配信される型の読み取りだけで、「0 以下は無効」の判断は UseCase が行う**） |
| 追加 | `master_data/domain/repositories/mst_player_level_repository.gd`、`mst_config_repository.gd`（契約） | `get_by_level(level: int) -> MstPlayerLevel`（無ければ null）、`get_by_id(id: String) -> MstConfig`（無ければ null）。DB が開けない・テーブルが無いときも null（例外にしない）。UseCase のテストで偽物に差し替えるので契約を作る |
| 追加 | `master_data/data/repositories/local_mst_player_level_repository.gd`、`local_mst_config_repository.gd` | `MasterDatabase.select_rows()` で読む（`mst_unit` の実装と同じ作り。キャッシュは持たない）。列は `mst_player_level`: `deploy_key, level, required_exp, max_stamina`、`mst_config`: `deploy_key, id, value, value_type`（api.md 6.5）。NULL は既定値（D3 と同じ考え方） |
| **変更しない** | `MasterDatabase.REQUIRED_TABLES`・同梱 `data/master.db` | 7 節。両テーブルは**必須にしない・同梱しない**（U2 の仮置き） |
| 追加 | `player/domain/entities/stamina_source.gd`（`StaminaSource`） | 回復計算の起点（login 時点の値。不変）: `current`・`recovered_at_unix`（`last_recovery_at` の UNIX 秒。読めなければ -1）・`rate_x100`（`recovery_rate_multiplier` を 100 倍した整数。読めなければ 0）・`max_stamina`（分からなければ -1）・`interval_seconds`（分からなければ 0）・`is_present`（`normal` の行があるか） |
| 追加 | `player/domain/entities/stamina_display.gd`（`StaminaDisplay`） | 表示値: `current`・`max_stamina`（-1 は不明）・`seconds_to_next`（-1 は出さない）・`is_present`。計算の結果で、保持しない |
| 追加 | `player/domain/services/stamina_recovery.gd`（`StaminaRecovery`） | **回復の純粋関数**（3 節）`static func calculate(source: StaminaSource, now_unix: int) -> StaminaDisplay`。状態を持たず `now` を引数で受ける（単体テストが時計に依存しない） |
| 追加 | `player/domain/services/diamond_total.gd`（`DiamondTotal`） | **ダイヤ合計の純粋関数**（4 節）`static func calculate(trx_diamond: Dictionary, trx_item_list: Array) -> int`。`is_delete` を真偽値・0/1 のどちらでも読む |
| 追加 | `player/domain/entities/home_summary.gd`（`HomeSummary`） | ホームの表示値の束: `is_logged_in`・`player_name`（null は空文字）・`player_id`・`level`（無ければ -1）・`coin`・`diamond_total`・`stamina_source`。画面の文字列は持たない |
| 追加 | `player/domain/entities/player_resource_ids.gd`（`PlayerResourceIds`） | U6 の定数: `COIN = "coin"`、`FREE_DIAMOND = "free_diamond"`、`STAMINA_TYPE_NORMAL = "normal"`、`STAMINA_RECOVERY_INTERVAL_KEY = "stamina_recovery_interval_seconds"`。サーバーの `mst_item.id`・`MstConfigKey` と一致させる二重管理（仮置き。コメントにサーバーの定義の場所を書く） |
| 追加 | `player/domain/use_cases/get_home_summary_use_case.gd` | `handle() -> HomeSummary`。`PlayerRepository.current()` と `MstPlayerLevelRepository`・`MstConfigRepository` から組み立てる（マスターは**ここで 1 回読む**。tick ごとに SQLite を引かない）。ホームを開いたときと `master_data_loaded` のときに呼ぶ |
| 追加 | `player/domain/use_cases/get_stamina_display_use_case.gd` | `handle(source: StaminaSource) -> StaminaDisplay`。`Clock` と `PlayerState` のサーバー時刻オフセットから `now_unix` を作り、`StaminaRecovery.calculate` を呼ぶだけ。tick・復帰のたびに呼ぶ |
| 追加 | `core/domain/clock.gd`（契約 `Clock`）、`core/data/clock/system_clock.gd`（`SystemClock`） | `now_unix() -> int`（端末の UTC の UNIX 秒）。実装は `Time.get_unix_time_from_system()`。デバッグ専用に `skew_seconds` を足せる（e2e の `--e2e-clock-skew`。製品では 0）。e2e が触れるよう `AppContext` に `debug_clock() -> SystemClock` を足す（`debug_auth_token_repository()` と同じ扱い。製品の画面は使わない） |
| 変更 | `player/domain/entities/player_state.gd` | `TRX_LIST_KEYS` から `trx_diamond_list` を外して **5 種**にし、**単数の `trx_diamond: Dictionary`**（無いとき `{}`）を足す。`server_time_offset_seconds: int`（既定 0）と `has_server_time: bool`（既定 false）を足す。`user_id()` などは変えない。**`is_empty()` は `sys_player` と `trx_lists` だけを見る（`trx_diamond` は含めない）**: ログイン後は `sys_player` が非空で足りる |
| 変更 | `player/domain/use_cases/apply_login_data_use_case.gd` | 入力に `trx_diamond: Dictionary`・`server_time_offset_seconds: int`・`has_server_time: bool` を足す（6 節）。再取得はしない（Q2） |
| 変更 | `player/presentation/home/home_presenter.gd`・`home.tscn` | 1-2・1-3 のとおり。`setup()` は 2 つの UseCase と `master_data_loaded` の購読元を受ける形にする（テストは偽物を渡す）。**`_exit_tree` でシグナルを切断し、`StaminaTimer` を止める** |
| 変更 | `login/data/api/login_response.gd`、`login/domain/entities/login_data_result.gd` | `trx_diamond`（`JsonReader.get_dict`）と、サーバー時刻のオフセット（`server_time_offset_seconds`・`has_server_time`）を足す。**`LoginDataResult._init` の引数に `trx_diamond: Dictionary`・`server_time_offset_seconds: int`・`has_server_time: bool` を足す**（既定値を付けて既存の呼び出し・テストを壊さない）。`TRX_LIST_KEYS` から `trx_diamond_list` を外す |
| 変更 | `login/data/repositories/login_api_repository.gd` | `Clock` を受け取り、応答の `Date` から `offset = サーバー時刻 − 端末時刻` を作る（3-3）。`login_use_case.gd` は値を `ApplyLoginDataUseCase` へ渡す |
| 追加 | `core/data/http/http_date.gd`（`HttpDate`） | `static func parse_to_unix(text: String) -> int`（RFC 7231 の `Sat, 14 Nov 2026 02:41:23 GMT` を UNIX 秒に。読めなければ -1）。`ApiClient` に `static func find_header(headers, name) -> String`（大文字小文字を区別しない。`has_master_update_required` と同じ走査）を足す |
| 変更 | `core/data/http/api_client.gd` | `X-Platform` の付与（5 節）。version など除外ルートを含め、`_build_headers()` の 1 か所で付ける |
| 変更 | `core/data/config/api_config.gd` | `platform()` を足す（5 節）。環境変数 `NEXUS_PLATFORM` → `[nexus] platform` → OS 既定 |
| 変更 | `app/app_context.gd` | 新しい Repository・UseCase・`Clock` の生成と、取得メソッド（`get_home_summary_use_case()` など）。`GetPlayerIdUseCase` は通知の購読（Toast）が使っているので残す |
| 変更 | `debug/e2e_driver.gd` | 8-2 の引数を足す。`E2E_RESULT: OK` にホームの値を出す |
| 変更 | `tests/` | 8-3。既存の `api_client_test.gd`・`login_response_test.gd`・`apply_login_data_use_case_test.gd`・`home_presenter_test.gd`・`debug/verify_auth_login.gd`（`PlayerState.TRX_LIST_KEYS` を使う）を新構成に合わせる |
| 変更 | `tools/prepare_release_project.py` | **変更不要の見込み**: 新規ファイルは `contexts/`・`master_data/`・`core/` の下で、製品の複製に含まれる分類に既に入る。`debug/` 側の追加（e2e の引数）は `EXCLUDE` 済み。S5 で `make check-release` を通して確かめる（9 節） |

依存の向き: `player` → `master_data/domain`（読み取りの契約）は許可、presenter が `check_master_data_use_case().master_data_loaded` を購読するのは「他コンテキストの公開 UseCase」の使い方で許可（architecture.md 2 節）。`player` は `login` の中身を知らない（login が `ApplyLoginDataUseCase` へ値を渡す今の形のまま）。

## 3. スタミナの表示

### 3-1. 式と置き場所（`StaminaRecovery.calculate`）

サーバーの式（api.md 8 節・overview 8 節 Q4・Q5 の影響）と同じ値を使い、**整数だけで計算する**（浮動小数の誤差で 1 点ずれないように。倍率 `"1.00"` を 100 倍の整数にする）。

入力: `StaminaSource`（起点。login 時点の `current_stamina`・`last_recovery_at`・倍率・最大値・回復間隔）と `now_unix`（サーバー時刻に補正した現在の UNIX 秒。3-3）。

1. **回復できない条件を先に判定する**（ここで返す）: `is_present` が偽 / 最大値が分からない（-1）/ 回復間隔が 0 / 倍率が 0 / 起点の時刻が読めない（-1）→ 現在値は起点のまま、`seconds_to_next = -1`（1-3 の表）
2. **最大値以上なら回復しない**（`current >= max_stamina`）: 現在値は起点のまま（丸めない。Q11）、残り時間なし。**この判定が経過時間の計算より先**。サーバーは最大値のとき `last_recovery_at` を進めない（経過が大きいまま）ので、先に判定しないと存在しない回復を足してしまう（api.md 2.3）
3. `elapsed = max(0, now_unix − recovered_at_unix)`（端末時計が過去へずれても負にしない）
4. `points = elapsed × rate_x100 ÷ (interval_seconds × 100)`（整数の切り捨て。サーバーの `floor(経過秒 × 倍率 ÷ 間隔)` と同じ）
5. `current = min(起点の current + points, max_stamina)`（途中で最大値に達したらそこで止める）
6. `current >= max_stamina` なら `seconds_to_next = -1`（最大値で残り時間を消す）。そうでなければ `seconds_to_next = ceil((points + 1) × interval_seconds × 100 ÷ rate_x100) − elapsed`（次の 1 点が入る時刻までの秒。整数の切り上げ。必ず 1 以上）

**二重加算にならない理由**: サーバーが login 応答の時点までの回復を `current_stamina` に足し、`last_recovery_at` をその分だけ進めて返す（余りの秒が残る。overview 8 節 Q4・Q5 の影響 1）。クライアントは**その 2 値を起点として一度だけ保持し、毎回その起点から `now` までを計算する**。計算結果を起点に書き戻さない（`StaminaSource` は不変）ので、tick を何回繰り返しても、画面を開き直しても同じ値になる。保持した `PlayerState` も書き換えない。

端数・倍率の丸め: 倍率は小数 2 桁の文字列（`"1.50"`）を `roundi(to_float() × 100)` で整数にする（`"1.00"` → 100）。残り時間は秒の整数で、`mm:ss`（1 時間以上は `h:mm:ss`）に直すのは presenter。倍率が 1 でも回復 1 点の秒数が割り切れない（例 間隔 300・倍率 1.50 → 200 秒）場合は上の切り上げで足りる。「満タンまでの時間」は出さない（Q4 は次の回復までだけ）。

### 3-2. 値の出どころ

| 値 | 出どころ | 読む時点 |
| --- | --- | --- |
| 現在値・`last_recovery_at`・倍率 | `PlayerState.trx_list("trx_stamina_list")` の `type == "normal"` の行（P1。`is_delete` が真なら無いものとして扱う） | `GetHomeSummaryUseCase`（ホームを開いたとき） |
| 最大値 | `MstPlayerLevelRepository.get_by_level(sys_player.level).max_stamina`（行が無ければ -1）。式 `50 + (level − 1) × 2` は持たない（Q3） | 同上と `master_data_loaded` のとき |
| 回復間隔 | `MstConfigRepository.get_by_id("stamina_recovery_interval_seconds").value_as_int()`。1 未満・-1 なら 0（Q12。定数で持たない。P5 のクライアント側） | 同上 |

`last_recovery_at` は先に正規表現 `^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$` で書式を確かめてから `Time.get_unix_time_from_datetime_string()` に渡す（0 を返す失敗と区別するため。0-e）。値は **UTC として読む**（api.md 3.2 のとおり印が付かない）。JSON の数値は float で来るので `current_stamina` は `int()` に直す。

### 3-3. 時刻の基準（U3）

`now_unix = 端末の UTC の UNIX 秒（Clock）+ server_time_offset_seconds`。端末時計がずれていても、ログイン時点のサーバー時刻に合わせる。

- **オフセットの作り方**: login の応答の `Date` ヘッダーを `HttpDate.parse_to_unix` で UNIX 秒にし、`offset = サーバー時刻 − 応答を受け取った時点の端末時刻（Clock）`。`Date` は秒の精度（切り捨て）で、通信の遅延も含むので、誤差は 1〜数秒。回復間隔（既定 300 秒）に対して許容する（仮置き。回復の「1 点が入る瞬間」が数秒ずれうる）。
- **`Date` が無い・読めない**: `has_server_time = false`・オフセット 0 とし、端末時計だけを使う（U3 の仮置き）。ログに警告を 1 回出す。
- **端末の時計を使う理由**: ホームを開いている間とバックグラウンド中の経過を同じ時計で測るため。単調時計（`Time.get_ticks_msec`）はモバイルのスリープ中に止まりうるので使わない（P4 の復帰時の経過が欠ける）。
- **ログ**: オフセットを作れたときも 1 行出す（`サーバー時刻のオフセット: N 秒`。秒数だけで、トークン・本文は出さない）。e2e は同じ値を `E2E_RESULT` の `offset=` にも出す。
- **オフセットは login のたびに更新**する（`PlayerState` と同じ寿命。メモリのみ・`session_expired` で消える）。他の API の応答の `Date` では更新しない（本機能では login の値だけ。必要が出たら別機能で `ApiClient` 側で一括更新する）。
- 開発では端末とサーバーが同じマシンなので、ずれは 0 になる。ずれの補正は `--e2e-clock-skew`（8-2）で確かめる。

### 3-4. 更新の頻度とバックグラウンド復帰（P4）

- **1 秒に 1 回**（`StaminaTimer`、`wait_time = 1.0`）で `GetStaminaDisplayUseCase` を呼び、スタミナのラベルだけを更新する（毎フレームにしない。残り時間が秒刻みなので 1 秒で足りる）。通貨など他のラベルは tick で触らない。
- **止める条件**: `StaminaDisplay.seconds_to_next == -1`（最大値・計算できない・行なし）のときは `StaminaTimer` を止める（無駄に起こさない）。復帰やマスター更新で状態が変わったら再計算し、必要なら再開する。ホームを離れたら（`_exit_tree`）止める。
- **復帰時（P4）**: `NOTIFICATION_APPLICATION_RESUMED`（アプリがバックグラウンドから戻った）と `NOTIFICATION_APPLICATION_FOCUS_IN` を `_notification` で受け、**端末の現在時刻でその場で計算し直す**（経過した分を一度に反映する）。バックグラウンド中は更新しない（タイマーは止まっているか、動いても画面に出ない）。この復帰処理の通知名・発火は実機・シミュレーターで確かめる（9 節。デスクトップのヘッドレスでは再現できない）。
- 表示値は毎回「その時点の `now`」から求める（`StaminaTimer` の遅れがあっても積み上がらない）。

### 3-5. マスターが更新されたとき

`master_data_loaded`（マスターの切り替え後）を受けて `GetHomeSummaryUseCase` を呼び直し、`StaminaSource` の最大値・回復間隔を差し替える。「最大値が分からない」から「分かる」へ変わる経路（初回に更新が間に合わなかった場合の回復）もこれで拾う（title-to-home 5 節の `X-Master-Update-Required` の更新が起動後に完了したとき）。版ずれ（U5）による login 応答とのずれは、次の login で直る（許容）。

## 4. 通貨の表示

### 4-1. Coin

`trx_wallet_list` の `mst_item_id` が `PlayerResourceIds.COIN`（`"coin"`）の行の `free_amount`（Q13）。`is_delete` が真の行は無いものとして扱う。行が無ければ 0。`paid_amount` は足さない（`gold` など他の行は見ない）。数量は `int()` に直す。

### 4-2. ダイヤの合計（D1〜D3・Q14・P6）

> **追従（free-diamond-item 実装済み）**: 暫定項 `trx_diamond.free_amount` は廃止され、合計は「有償 `trx_diamond.paid_amount` + 無償 `trx_item_list` の `free_diamond`」だけになった（`free_amount` のキーが来ても足さない）。正は [free-diamond-item のクライアント設計 2 節](../free-diamond-item/client_design.md)。以下の暫定項・二重カウントの記述は移行期間の経緯。

ダイヤの元は 3 か所に分かれる。login の応答（api.md 2.5・2.6・4 節）:

| 元 | 中身 | 現在 | 別機能 free-diamond-item の完了後 |
| --- | --- | --- | --- |
| `trx_diamond.paid_amount` | 有償 | **端末の platform の 1 行**（`X-Platform` の値の行。他 platform の行は返らない。無ければ `trx_diamond` が `null`） | 変わらない |
| `trx_diamond.free_amount` | 無償（暫定）。ログインボーナスの `free_diamond` などの付与先（サーバーは付与の既定 platform を `X-Platform` の値にするので、端末の行に入る） | あり | **廃止され、キーが応答から消える**（D4） |
| `trx_item_list` の `mst_item_id == "free_diamond"` の行の `free_amount` | 無償。サインアップ時の初期付与 50 がここに入る（`trx_diamond` には入らない） | 初期付与の分だけ | すべての無償がここに集約 |

**足す規則（これだけ）**:

```
有償   = trx_diamond.paid_amount                      （trx_diamond が null・{}・キー無し → 0）
無償   = trx_diamond.free_amount                      （キーが無い・null → 0。暫定の項）
       + Σ trx_item_list[mst_item_id == "free_diamond"].free_amount   （is_delete が真の行は除く。行が無い → 0）
合計   = 有償 + 無償
```

- `trx_item_list` の `free_diamond` の行の **`paid_amount` は足さない**（有償は `trx_diamond` だけ。同じ値を 2 経路で足さない）。`trx_diamond` に platform は無関係（応答がすでに端末の行だけ。**クライアントは platform でダイヤの行を選ばない**）。
- **二重カウントにならない理由**: 無償の 2 つの置き場（`trx_diamond.free_amount` と `trx_item_list` の `free_diamond`）は、サーバーの書き込み経路が分かれていて**同じ無償ダイヤを両方に載せない**（初期付与の 50 は `trx_item` だけ・ボーナスなど既存の付与は `trx_diamond.free_amount` だけ。api.md 4 節・db.md 8.6、D4）。別機能 free-diamond-item は既存の無償を `trx_item` へ**移して**から `trx_diamond.free_amount` の列を削除する（D4）ので、移行の後は暫定の項が自然に 0 になり、**コードの変更なしで正しい合計のまま**（暫定の項の削除は掃除）。overview 8 節の 4（切り替えは小さな追従）の実体は「暫定の項を消す」だけ。
- 「`trx_item` の `free_diamond` だけを足す」と現在は既存・ボーナスの無償が消え、「`trx_diamond` だけ」と新規ユーザーの初期 50 が出ない。**どちらかの置き換え方式にせず、キーが在るかで足す**のが安全。
- **別機能 free-diamond-item への申し送り（二重カウント回避の前提。人の決定 D4）**: 既存の無償の移行は **`trx_item` の `free_diamond` へ移して `trx_diamond.free_amount` の列を削除する。コピーして残さない**。残すと同じ無償を 2 回足す。この前提が崩れる設計になったら、クライアントの合算規則（4-2）を先に直す。
- **P6 との関係（人の決定 D1）**: overview の P6 の「暫定の無償は `trx_diamond` の `free_amount`」は、サーバー設計 db.md 8.6・api.md の暫定の注記（`trx_diamond.free_amount` ＋ `trx_item` の `free_diamond`）に従って読む。無償ダイヤは `trx_item` の `free_diamond` で管理し（D1）、サインアップ時の初期 50 もそこに入るため、暫定でも `trx_item_list` の `free_diamond` を足す。
- 表示は合算で、サーバーのダイヤ消費の判定（`DiamondService` は `trx_item` を見ない。db.md 8.6）とは食い違う。新規ユーザーはダイヤ 50 と表示されても、ガチャの消費は残高 0 になる。クライアントでは直さない。

## 5. X-Platform ヘッダー（サーバー api.md 10 節）

### 5-1. 付与

`ApiClient._build_headers()` の 1 か所で、**`ApiClient` を通る全リクエストに `X-Platform: <値>` を付ける**。

| 呼び出し | 付ける | 理由 |
| --- | --- | --- |
| ゲーム API（`request()` の全部: sign_up / sign_in / login / agreement など） | 付ける | 必須（欠落は 299 / 99003）。サーバーの `POST /auth/version`（認証済み）も必須だが、**クライアントは使わない**（version は GET のみ） |
| `/auth/refresh_token`（`ApiClient` が `_send` で送る） | 付ける | `maintenance` グループ内で必須。`_send` を通るので同じ場所で付く |
| `GET /auth/version`（`master_data` のバージョン確認） | **付ける**（任意だが付けて害は無い。分岐を増やさないため一律） | 除外ルートだが付けるのは自由（api.md 10.2） |
| 配信ホストのダウンロード・規約本文（`ApiClient.download()`） | **付けない**（今のまま `_send_http` を直接呼び、独自のヘッダーだけ） | API ではない（配信ホストは ADR 0001 のクライアント設定の別ホスト）。platform を他ホストへ送らない |
| Toast の `/broadcasting/auth` | 付けない（変更なし） | `maintenance` グループ外で不要。`ApiClient` を通らない |

- **署名には含めない**（Q23）。sign_up の署名は今のまま（`AuthApiRepository` の署名関数は変えない）。`extra_headers` の署名ヘッダーと `X-Platform` が重ならない。
- `X-Platform` は 1 起動の間で変わらないので、`ApiClient` は `ApiConfig.platform()` を**組み立て時に 1 回**受け取って持つ（`configure()` と同じ要領。テストは値を差し替えられる）。

### 5-2. 値の決め方（`ApiConfig.platform()`）

`ApiConfig` の他の設定と同じ順（上が優先）:

1. 環境変数 `NEXUS_PLATFORM`
2. `project.godot` の `[nexus]` の `platform`
3. OS の既定: `OS.get_name()` が `"iOS"` → `Apple`、`"Android"` → `Google`、**それ以外（macOS・Windows・Linux・エディタ・Web）→ `Apple`**（デスクトップの開発・e2e の既定。サーバーの付与の既定と開発シードが `Apple` なので揃える。仮置き）

- 許可値は `Apple` / `Google`（完全一致）。上書きの値は前後の空白を除き**大文字小文字を区別せず**正規形に直す（`google` → `Google`）。それ以外（`iOS`・空文字など）は**警告を出して OS の既定に戻す**（誤った値を送って全 API が 99003 になるのを避ける。サーバーは不正値を拒否する）。OS 名から決める部分は引数で OS 名を受ける純粋関数（`platform_from_os_name(name)`）にして単体テストする。
- リリースビルドでの上書きは `[nexus]` の `platform`（製品は iOS・Android で OS の既定が正しいので、通常は設定しない）。
- U7 の答え: クライアントは自分の OS を知っているので、`BuyRequest` の `platform`（課金）と同じ値にできる。**ダイヤの行の選択には使わない**（4-2。サーバーが端末の行だけを返す）。

### 5-3. 欠落・不正値のエラー（299 / 99003）

- `ApiClient` は既存どおり HTTP 299 を `BUSINESS`（`error_code` = 99003）に分類する。**特別な画面は作らない**（クライアントの実装の誤りで、利用者は直せない。リトライしても直らない）。利用者には汎用の「エラーが発生しました (コード: 99003)」が出る（title-to-home 1-3）。
- 開発者が気づけるよう、`ApiClient` は 299 の `error_code` が 99003 のとき `push_error("X-Platform がサーバーに拒否されました（設定: <値>）")` を 1 回出す（値は `Apple` / `Google` のどちらかなので出してよい。トークン・本文は出さない）。コード 99003 はサーバー設計で仮置きなので、分類（`BUSINESS`）はコードの値に依存させない。
- 冪等キー: 99003 は冪等ミドルウェアより外で返り保存されないが、`BUSINESS` なので title-to-home 3-4 のとおり再試行時に新しいキーを作る（挙動は変えない）。

### 5-4. 旧版互換

サーバーの Q22 の決定（旧版は考慮せず S3 と同時に必須化）に従う。**クライアントの S5 は、サーバーの S3 と同じリリースで出す**前提（片方だけ先に出ると全 API が失敗する）。配布状況の確認はサーバー側の S3 前提作業（api.md 10.10）。

## 6. 登録・login 応答の取り込み

login の応答（api.md 2 節・4 節）を `LoginResponse` で型付きにし、`ApplyLoginDataUseCase` で `PlayerState` に置く（title-to-home 4 節の流れのまま）。**再取得しない**（Q2）。差分だけ:

| 項目 | 取り込み |
| --- | --- |
| `sys_player` | 今のまま辞書。`name` は null になりうる（`str(null)` が `"<null>"` になる落とし穴があるので、`GetHomeSummaryUseCase` は `sys_player.get("name")` が `String` のときだけ採用し、それ以外は空文字） |
| `trx_stamina_list`・`trx_wallet_list`・`trx_item_list` | 今のまま `JsonReader.get_array`（null・欠落 → `[]`）。新規ユーザーは空ではなく 1 行ずつ入る（stamina `normal` 1 行、wallet `coin` 1,000、item `free_diamond` 50）。**空配列も正常**（既存プレイヤーは行が無い。1-3 の表） |
| **`trx_diamond`（単数）** | `JsonReader.get_dict(data, "trx_diamond")`（null・欠落・型違い → `{}`）を `PlayerState.trx_diamond` に置く。旧キー `trx_diamond_list` は**読まない**（サーバー設計の更新と同時に切り替える） |
| `is_delete` | **真偽値（Q8）**。移行の間は 0/1 の整数も来うる（api.md 3.1）ので、`is_delete` を読む箇所（スタミナ・ウォレット・アイテム・ダイヤの行の除外）は `true` と 0 以外の数値を「削除」、`false` と 0・キー無しを「有効」として扱う小さな関数 1 つ（`PlayerState` の共有ヘルパー）に集める。サーバーは削除済みの行を返さないので、実際は保険 |
| 数量 | JSON の数値は float で来る。`int()` に直して使う（保持は元のまま） |
| サーバー時刻 | 応答ヘッダーの `Date`（3-3）。本文には無い |
| 保持と破棄 | メモリのみ。`session_expired` で `PlayerState` とオフセットを空にする（今の仕組み。`LocalPlayerRepository.clear()`） |

`login_response_test.gd`（`trx_diamond_list` を前提）と `PlayerState.TRX_LIST_KEYS` を使う箇所（`apply_login_data_use_case_test.gd`・`debug/verify_auth_login.gd`）は、5 種 + 単数の形に直す。

## 7. マスターデータ（`master_data`）

追加するのは **`mst_player_level` と `mst_config` の読み取り**（2-2 の Repository と読み取りモデル）。配信ファイルの用意（デプロイ・エクスポート）はサーバー側の運用作業で、S5 の前提（確認手順 8-1）。

| 項目 | 方針 |
| --- | --- |
| 同期 | 変更なし。`CheckMasterDataUseCase` は version の `tables` の全テーブルを差分取得するので、配信に両方が入れば自動で取り込まれる（0-f） |
| `REQUIRED_TABLES` | **変えない（必須にしない）**。必須にすると、配信が無い環境（開発の初期状態・録画環境）で更新全体が `FAILED` になり、`mst_gacha` など既存の更新まで止まる。両テーブルは「あれば読む」 |
| 同梱 `data/master.db` | **入れない**（U2 の仮置き）。同梱するとサーバーの `mst_player_level` を二重管理し、回復間隔は「定数で持たない」（Q12）の趣旨に反する。代わりに、読めないときは 1-3 の表のとおり**現在値だけを出し、回復を計算しない** |
| 配信が無い／更新失敗のとき（U2） | 同梱 DB（または前回取得済みの DB）には両テーブルが無く、Repository が null を返す → 最大値「--」・回復なし（1-3）。title-to-home 5 節のとおり**止めずに続行し、タイトルで通知済み**（「マスターデータを更新できませんでした」）。ホームでは追加の通知を出さない。初回起動で更新に失敗したまま入った端末は次回起動まで読めない（title-to-home 5 節・未解決 13 と同じ） |
| 読み方 | `MasterDatabase.select_rows("mst_player_level", ...)`。テーブルを持つ DB が無いときは空配列（0-f）なので、Repository は null を返すだけで例外・エラーにしない |
| 更新の反映 | `master_data_loaded` でホームが `GetHomeSummaryUseCase` を呼び直す（3-5） |
| 版ずれ（U5） | 回復間隔・最大値は最後に更新したマスターの値。サーバーとの差は表示の差で、次の login・マスター更新で直る（許容） |
| 同梱 DB の更新手順 | 不要（変更しない）。`docs/MASTER_DATA.md` に「`mst_player_level` と `mst_config` は同梱せず、配信から読む」を追記する（6 節の表） |

## 8. 確認手順（S5 で動画に撮る操作と期待結果）

### 8-1. 前提

- サーバー: `NexusMobileGameServer-Laravel` で `make up`（API :8090、配信 :8091）。**S3 完了**（`mst_config` の新設、回復間隔の MstConfig 化、`X-Platform` 必須、サインアップ時の初期付与、`is_delete` の真偽値化、login の `trx_diamond`（単数））。`make migrate-fresh && make seed`（`MstConfigSeeder`・`MstPlayerLevelSeeder`・`mst_item` の `free_diamond` を含む）。
- **マスターの配信（S5 の前の運用作業）**: 運営ツール（:8091）の `POST /master-import/export` を開発環境で実行し、`sys_deploy_master_table` に `mst_player_level`・`mst_config` の行があり、`GET /auth/version` の `master.tables` に両方があることを確認する（api.md 6.4。実行は主担当の運用作業）。**動画用シード（`RecordingDeploySeeder`）は配信ファイルを作らない**（別の Server タスク。overview 8 節 Q12 の影響 4）ので、それが済むまでの動画は開発環境のエクスポート済みサーバーで撮る。
- 値の作り方（開発 DB。S5 で実際に通る SQL を確認する。仮置き）:
  - **短い回復間隔**: `mst_config` の `stamina_recovery_interval_seconds` を 300 → 20 に更新して再エクスポートし、クライアントを再起動（version の `needs_update` で `mst_config` を取得）。**確認後に 300 へ戻して再エクスポート**。サーバーの login の回復計算も同じ値を使うので、サーバーとクライアントで食い違わない。
  - **スタミナを減らしたプレイヤー**: 新規作成後、そのプレイヤーのシャード DB（`trx1`〜）の `trx_stamina`（`type = 'normal'`）の `current_stamina` と `last_recovery_at`（UTC の `Y-m-d H:i:s`）を直接更新する。
  - ダイヤ・コイン・アイテムの値は、同じく `trx_diamond`・`trx_wallet`・`trx_item` を直接更新する。
- クライアント: 縦長 1080x1920。録画は `godot --path <client> --write-movie <out.avi> --fixed-fps 30 --resolution 1080x1920 -- --e2e-case=<名前> --e2e-dwell=2 [引数]`（`docs/workflow/recording.md`）。
- **レート制限（sign_up は IP あたり 10 回/時間。title-to-home 7-1）**: 新規ユーザーの作成は **ケース 1 と 11 の 2 回だけ**（ケース 1 で作ったプレイヤーを、`--e2e-reset` を付けずに DB を書き換えて使い回す: ケース 2〜6・8・10・12。ケース 7 は端末のマスターだけを消す。ケース 9 は最後に、そのプレイヤーの行を削除して使う）。撮り直しは Redis のカウンターを消す（recording.md）。
- **マスターの前提の整理**: 上の「両テーブルをエクスポート済み」はケース 1〜6・8〜13 の前提。**ケース 7 は配信を消さず**、端末側の `user://master`・`master_state.json` を消して配信ホストだけを不達にして再現する（version は API ホストから取れるので `needs_update` が真になり、ダウンロードが失敗する。端末に取得済みの DB があると、または `needs_update` が偽だとダウンロード自体が起きないため）。
- 期待結果は画面の文字列で確認し、動画から 1 枚ずつ抜いて見る。

### 8-2. e2e ドライバーの追加（`debug/e2e_driver.gd`。製品の複製から除外される）

| 引数 | 内容 |
| --- | --- |
| `--e2e-home-hold=<秒>` | ホームで止まる秒数。**`HOME_QUIT_DELAY`（2 秒）+ `--e2e-dwell` に加算**する（置き換えない。既定 0）。スタミナの回復を画面に出し続けて撮るため（`--e2e-dwell` は全画面に効くので別にする） |
| `--e2e-clock-skew=<秒>` | `AppContext.debug_clock().skew_seconds` に設定し、端末時計がずれた状況を作る（3-3 のオフセット補正の確認） |
| `--e2e-omit-platform` | `AppContext.api_client().set_platform("")` で `X-Platform` を付けない状態にする（99003 の表示の確認）。`ApiClient` は「platform が空文字なら付けない」とし、`set_platform()` を足すだけにする（フラグを増やさない。製品は `ApiConfig.platform()` の値が必ず入る） |
| （出力の追加） | `E2E_RESULT: OK` にホームの値を足す: `player_id=… name=… level=… stamina=現在値/最大値 remain=… coin=… diamond=… login_stamina=<login 応答の current_stamina> open_stamina=<ホームの最初の表示値> offset=<サーバー時刻のオフセット秒。無ければ none>`。画面の文字ではなく、`GetHomeSummaryUseCase` と `GetStaminaDisplayUseCase` の結果を出す（目視と照合する） |

`NEXUS_PLATFORM=Google` などの環境変数は `ApiConfig` が読む（引数にしない）。

### 8-3. ケース

| # | 前提状態 | 操作 | 期待結果 |
| --- | --- | --- | --- |
| 1 | 新規ユーザー（`--e2e-reset`）、規約なし。ログインボーナス 1 日目の報酬の種類を事前に確認しておく（`gold` など。`free_diamond` / `coin` / スタミナなら下の値に報酬分が加わる。S5 で seed を確認） | 起動 → 自動 → ホームで `--e2e-home-hold=5` | ホームに: 名前（ランダム 8 文字）、`ID: <8 文字>`、`Lv.1`、**スタミナ「50 / 50」（レベル 1 の `max_stamina`）で残り時間なし**、コイン「1,000」、**ダイヤ「50」**（有償 0 + 無償 50。無償は `trx_item` の `free_diamond`）、「メール」「お知らせ」のボタンと数字なしのバッジ枠。ボタンを押しても何も起きない。`E2E_RESULT` に同じ値。**サーバーのログに `X-Platform: Apple` が付いた sign_up / login が見える**（リクエストログがあれば。無ければ DB の `trx_diamond.platform = Apple`） |
| 2 | 1 と同じ端末で 2 回目の起動、同日 | 起動 → 自動 | 同じ ID・名前。値は login の値（ログインボーナスは受取済み）。ダイヤは 50 のまま（二重に 100 にならない）。`Date` ヘッダーが login で読めている（ログに「サーバー時刻のオフセット N 秒」。開発では 0〜1） |
| 3 | 回復間隔 **20 秒**（8-1）。ケース 1 のプレイヤーのスタミナを `current = 46`・`last_recovery_at = 現在（UTC）` にしてから起動（起動の所要時間は数秒〜10 秒以上で変わる） | 起動 → ホームで `--e2e-home-hold=120` | ホームの最初の表示は **login 時点の値（46〜起動の所要時間ぶん進んだ値。`open_stamina` = `login_stamina`）**。そこから **50 まで 1 点ずつ**、約 20 秒ごとに増え、**残り時間が減り（20 → 0 秒）、増えるたびに戻る**。50 で増加と残り時間が止まる（残り時間の行は消える）。tick は 1 秒刻み |
| 4 | **二重加算の確認**: 回復間隔 20 秒。`current = 40`・`last_recovery_at = 現在の 50 秒前`（に設定してから起動） | 起動 → ホームで `--e2e-home-hold=60` | サーバーが login で `floor((50 + 起動の所要秒) ÷ 20)` 点（所要 10 秒未満なら 2 点 → 42、10〜30 秒なら 3 点 → 43）を反映して返す。**期待は `open_stamina` が `login_stamina`（サーバーが返した値）と一致すること**（二重加算なら、それより 2 点以上多い。例 44 以上）。残り時間は 20 秒以内で、その後 1 点ずつ増える |
| 5 | 最大値超過: `current = 55`（レベル 1・最大 50） | 起動 | 「55 / 50」（丸めない）、残り時間なし、時間が経っても変わらない |
| 6 | **端末時計のずれ**: 3 のプレイヤー（`current = 46`・`last_recovery_at = 現在` に戻す） | `--e2e-clock-skew=3600`（端末が 1 時間進んでいる）を付けて起動、`--e2e-home-hold=120` | `offset` が約 -3600 秒（`E2E_RESULT` とログ）。**ケース 3 と同じ増え方**になる（補正が無いと即 50 になる）。`--e2e-clock-skew=-3600` でも同様 |
| 7 | **マスター未配信（端末側で再現）**: ケース 1 のプレイヤーのスタミナ `current = 42`。**端末の `user://master/` と `user://master_state.json` を消し**（保存データの場所は title-to-home 7-1）、`NEXUS_MASTER_BASE_URL=http://localhost:9`（配信ホストだけ不達。version は API ホストから取れて `needs_update` が真）で起動する。（配信自体に両テーブルが無い状態は、`sys_deploy_master_table` が空の開発の初期状態で別途確認できる。同じ表示になる） | 起動 | タイトルで「マスターデータを更新できませんでした…」（既知）。ホームは**クラッシュせず**、スタミナ「42 / --」・残り時間なし・増えない。ほかの項目（名前・ID・レベル・コイン・ダイヤ）は出る |
| 8 | `mst_player_level` はあるが `mst_config` の行が無い（`mst_config` の行を消して再エクスポート。サーバーは既定の 300 秒で続ける）。**行を消して再エクスポートしたとき、配信ファイル・`master.tables` に `mst_config` が空のテーブルとして載るか、テーブルごと載らないかは S5 で確認する**（どちらでも `get_by_id` が null → 同じ表示になる設計） | 起動 | 「42 / 50」だが残り時間なし・増えない（P5）。サーバーの値とずれるが次の login で直る |
| 9 | スタミナ行なし・`coin` の行なし・`trx_diamond` が null（サインアップ時に作られるので、**S3 前に作った既存プレイヤーを使う**か、ケース 1 のプレイヤーの `trx_stamina`・`trx_wallet` の `coin`・`trx_diamond` の行を削除して使う。他のケースの後に行う） | 起動 | スタミナ「-」、コイン「0」、ダイヤは `trx_item` の分だけ（無ければ 0）。クラッシュしない |
| 10 | **ダイヤの合算**: ダイヤの行の `paid_amount` = 30・`free_amount` = 100、`trx_item` の `free_diamond` の `free_amount` = 50。他 platform（`Google`）の `trx_diamond` の行に `paid_amount` = 999 を入れておく | 起動（Apple） | ダイヤ「180」（30 + 100 + 50）。**999 は出ない**（応答は端末の行だけ） |
| 11 | `NEXUS_PLATFORM=Google` | 新規ユーザーで起動 | sign_up・login が成功し、DB の `trx_diamond.platform = Google`。ホームのダイヤは 50（無償の初期付与）。`NEXUS_PLATFORM=iOS`（不正値）では警告が出て `Apple` に戻る |
| 12 | `--e2e-omit-platform` | 起動 | タイトルで「エラーが発生しました (コード: 99003)」と再試行（直らない）。ログに X-Platform の `push_error`。`GET /auth/version` は通る（マスターの確認は進む） |
| 13 | 縦長・サイズ: 録画・`--e2e-shot` を `1080x1920`。ダイヤを 999,999,999 にした状態と、1 つ小さい解像度（720x1280）でも撮る | ホーム | はみ出し・切れ・折返しがない。ボタンが画面下のセーフエリアに隠れない。ラベルにキーの文字列（`stamina` など）が出ていない。名前が長くても省略記号で収まる |
| 14 | バックグラウンド復帰（P4）: 3 のプレイヤー（回復間隔 20 秒。`current = 40`・`last_recovery_at = 現在`） | シミュレーター・実機でホームを開き、アプリを 50 秒バックグラウンドにして戻す | 戻った瞬間に、経過した分（2〜3 点）が一度に反映される。**自動化できない見込み（手動。撮れなければ PR に「未確認」と書く）** |

単体テスト（GdUnit4）で確かめる: `StaminaRecovery`（最大値判定が先・倍率 1.5・端数・負の経過・最大値超過・起点が読めない・間隔 0）、`DiamondTotal`（`trx_diamond` が null / `{}`・`free_amount` キー無し・`free_diamond` の行が無い・`is_delete` 真・`paid_amount` を足さない）、`HttpDate`、`ApiConfig.platform`（OS 名・上書き・不正値）、`ApiClient` のヘッダー（`X-Platform` が `request` に付き、`download` に付かない）、`GetHomeSummaryUseCase`（マスターが null のとき）、`HomePresenter`（各状態の文字列・`_exit_tree` の後始末）、`LoginResponse`（`trx_diamond` の null・欠落）。

## 9. 未解決点

### 確認事項

なし。C1〜C3 は既存の人の決定から答えが出たので反映済み（下の表）。

| # | 内容 | 結論 |
| --- | --- | --- |
| C1 | 暫定でも `trx_item_list` の `free_diamond` を足す | 4-2 のとおり（人の決定 D1。P6 は db.md 8.6・api.md の注記に従う） |
| C2 | free-diamond-item の移行は「移して列を削除」（コピーしない） | 4-2 に申し送りを明記（人の決定 D4） |
| C3 | 同梱 `data/master.db` に `mst_player_level`・`mst_config` を入れない | 仮置き。配信が無い環境では最大スタミナ「--」・回復なし（U2。1-3・7 節） |

### 仮置き（既定案で進める）

| # | 内容 | 既定案 |
| --- | --- | --- |
| K1 | 読めないときの表示（U2・P5）: 最大値が分からない → 「42 / --」・回復なし。回復間隔が分からない → 回復なし。倍率・時刻が読めない → 回復なし | 1-3 の表 |
| K2 | 導線ボタンの文言と順序（「メール」「お知らせ」）・バッジ枠（輪郭だけの円）。押下は何も起きない（P3） | 1-2 |
| K3 | 桁区切りあり。名前なしの文言「名前なし」（Q7）。ID は「ID: ＋ my_id」 | 1-3 |
| K4 | スタミナの更新は 1 秒刻み（`Timer`）、最大値などで止める。復帰時はその場で計算し直す（P4） | 3-4 |
| K5 | サーバー時刻のオフセットは login の `Date` だけで作り、login のたびに更新（他の応答では更新しない）。誤差は数秒を許容。`Date` が無いときは端末時計 | 3-3 |
| K6 | 端末の時計は `Time.get_unix_time_from_system()`（単調時計を使わない） | 3-3 |
| K7 | `X-Platform` の既定（デスクトップ・エディタ・Web は `Apple`）、不正な上書きは警告して OS の既定に戻す、`GET /auth/version` にも付ける、`download()` には付けない、99003 は汎用表示 + `push_error` | 5 節 |
| K8 | Coin・無償ダイヤ・スタミナの種類・回復間隔のキーはクライアントの定数（U6） | `PlayerResourceIds`（2-2） |
| K9 | 計算の純粋関数（`StaminaRecovery`・`DiamondTotal`）は **`player/domain/services/`**（新しい置き場。案 A、採用）。`architecture.md` は「entities は独自の計算・判定を足さない」「ドメインサービスは採用しない」とあるので、**そのどちらにも例外を設ける**（下の 6 の表）。案 B: `entities/` に置く（architecture.md の entities の記述を直す。計算を値の近くに置ける反面、読み取りモデルの原則が崩れる）。`Clock` は `core/domain` の契約。S5 で `make check-deps`（`tools/check_dependencies.py`）が `domain/services/` を許すことを確かめ、許さなければチェッカーを直す | 2-2 |
| K10 | 行が無いときの `trx_diamond` を `null` で受ける（サーバー設計の更新 PR に従う。仮置きは値が無いとき `null`）。項目なし（キー欠落）でも同じ扱い | 6 節 |
| K11 | クライアントの S5 はサーバーの S3 と同時にリリース（旧版互換なし。サーバー Q22） | 5-4 |
| K12 | 動画の e2e ドライバー追加引数（`--e2e-home-hold` `--e2e-clock-skew` `--e2e-omit-platform`） | 8-2 |

### 実行で確かめる点

| # | 内容 | 状況 |
| --- | --- | --- |
| E1 | `Date` ヘッダーが `ApiClient` の結果に残る | **確認済み（読んだ）**。`GET /auth/version` に `Date` が付くのも**確認済み**（curl）。**login（POST）の応答に付くか**は S5 のケース 2 で確認 |
| E2 | `Y-m-d H:i:s` を UTC として読む（Godot 4.7.2） | **確認済み**（0-e）。失敗は 0 を返す → 書式検査が要る |
| E3 | サーバーが `X-Platform` を受理する・login が `trx_diamond`（単数）を返す・`is_delete` が真偽値で来る・新規ユーザーに初期値が入る | S3 の完了後、ケース 1・10・11 で確認（サーバー設計の更新 PR・S3 に依存） |
| E4 | `mst_player_level`・`mst_config` が実際に配信に載る | 運用作業の後、`GET /auth/version` と 8-1 の確認 |
| E5 | バックグラウンド復帰の通知（`NOTIFICATION_APPLICATION_RESUMED` / `FOCUS_IN`）が実機・シミュレーターで来て、経過が一度に反映される | ケース 14（手動。未確認になりうる） |
| E6 | セーフエリア（`DisplayServer.get_display_safe_area()` の物理ピクセル → ビューポート座標への変換。1-2）で上下の余白が崩れない。ノッチ付きの端末で、変換前後の値をログに出して確かめる | 実機・シミュレーター（ケース 13） |
| E7 | `make check-release` が通る（新規ファイルの分類） | S5 |
| E8 | ログインボーナス 1 日目の報酬の種類（ケース 1 の期待値に影響） | S5 で seed を確認 |

### ドキュメント更新（S5 で行う。ここでは一覧だけ）

| ファイル | 直す内容 |
| --- | --- |
| `.claude/api.md` | login の応答に `trx_diamond`（単数）。`X-Platform` ヘッダー（全リクエスト・`download` は除く・値の決め方・99003）。`Date` からのサーバー時刻の補正 |
| `.claude/README.md` | login の取得項目の例（`trx_diamond_list` → `trx_diamond`）、ホームの表示項目、`NEXUS_PLATFORM` と `[nexus] platform` |
| `.claude/architecture.md` | `core/domain/clock.gd`。**entities の「独自の計算・判定を足さない」と 4 節の「ドメインサービスは採用しない」に例外を設ける**: 表示専用の計算（F9 の例外。スタミナの自然回復の表示とダイヤの合算だけ）の純粋関数に限り、`contexts/{context}/domain/services/`（状態を持たない静的関数）を置いてよい。階層図・3 節の表にも `domain/services/` を足す（案 B なら entities の記述を直す。K9） |
| `docs/MASTER_DATA.md` | `mst_player_level`・`mst_config` を配信から読む（同梱しない。`REQUIRED_TABLES` に入れない） |
| `.claude/implementation-history.md` | この機能の実装を追記 |
| `CLAUDE.md` | `[nexus]` の設定に `platform` / `NEXUS_PLATFORM` を追記 |
