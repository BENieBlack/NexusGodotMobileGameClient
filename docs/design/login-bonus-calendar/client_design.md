# ログインボーナスのカレンダー表示とアイテムアイコン クライアント設計

- 要件（正。ここには複製せず記号で指す）: `Nexus/docs/requirements/login-bonus-calendar.md`（T = 今日の段、C = カレンダー、K = スタンプ、D = データ、I = アイコン、H = ホームの導線、R = 再受け取り、Q = 確認事項。Q1〜Q31 は確定済み）
- 全体設計（正。マージ済み）: `Nexus/docs/design/login-bonus-calendar/overview.md`（責務の分担 2 節、API の変更 3 節、判定 4 節、非機能 5 節、S4 への宿題 8 節、決定 D-1〜D-5・未解決 U-1〜U-10）
- サーバー設計（S2。**未マージ・下書き**）: `NexusMobileGameServer-Laravel/docs/design/login-bonus-calendar/{db,api,sequence}.md`。**この文書の API の項目名・型・エラーコードは overview の名前で仮置きしたもの**。S2 のマージ後に差分を直して確定する（12 節の「S2 マージ後の差分の洗い出し」）
- 前提: [title-to-home](../title-to-home/client_design.md)（login・冪等キー 3-4・エラー 1-3）、[home-player-info](../home-player-info/client_design.md)、[free-diamond-item](../free-diamond-item/client_design.md)（名前の引き 3-2・3-3）
- 規約: `.claude/architecture.md`（3 層・master_data・依存ルール）、`.claude/coding-standards.md`（コメント）、`.claude/api.md`

旧クライアントは未配布で互換は持たない。ただし**新クライアント × 旧サーバー**（新キー・新 API が無い）では、カレンダーを出さず今の文字の画面に落とす（D4）。サーバーが先、クライアントは同じ時期に追従する。

## 0. 現状の確認結果（設計の前提。コードを読んで確かめた）

| # | 確認したこと | 場所 |
| --- | --- | --- |
| a | ログインボーナス画面は通信しない。`LoginBonusPresenter` が `GetLoginBonusDisplaysUseCase` の結果を 1 つの Label に複数行で出し、画面のどこでもタップ（`_input` でマウス左・タッチ）でホームへ。`_is_leaving` で二重遷移を防ぐ。アニメーションは無い | `contexts/login/presentation/login_bonus/` |
| b | 読み取りモデルは `LoginBonus`（6 項目）と `LoginBonusDisplay`（`bonus`・`item_name`）だけ。日数・全日・受け取り済みを持つモデルは無い。保持先 `LocalLoginBonusRepository` は `login_bonus_list` の配列だけをメモリに持つ | `contexts/login/domain/entities/`、`data/repositories/` |
| c | `LoginResponse.from_dict` は `sys_player`・`trx_diamond`・trx 5 種・`login_bonus_list` だけを読む（未知のキーは無視）。null・欠落は `JsonReader.get_array/get_dict` で `[]`/`{}` | `contexts/login/data/api/login_response.gd` |
| d | `LoginUseCase.handle` は取得 → `ApplyLoginDataUseCase`（player の公開 UseCase）→ `LoginBonusRepository.replace`。冪等キーは呼び出し元が持ち、`IdempotencyKey.can_reuse(kind)` で再利用を決める | `login_use_case.gd`、`core/domain/idempotency_key.gd` |
| e | `SceneRouter.goto_login_bonus()` は既にある。呼ぶのは agreement だけ。ホームからの導線は無い。遷移は `change_scene_to_file` で、**引数を渡す口は無い** | `app/scene_router.gd` |
| f | ホームは `_ready` で `reload()` し、PlayerRepository の現在値から全ラベルを作る。ホームを離れて戻ると `_ready` が走るので、再読み込みで最新になる。ナビ列 `NavRow` にメール・お知らせのボタン（`pressed` は未接続）とバッジの枠がある。`HomePresenter` はルーターを持たない（`setup` は UseCase 2 つと Signal） | `contexts/player/presentation/home/` |
| g | ホームの値は `Margin/Root/{StaminaPanel,CurrencyRow/CoinPanel,CurrencyRow/DiamondPanel}/VBox/*ValueLabel` の Label。コインは `trx_item_list` の `mst_item_id = coin`、無償ダイヤは `free_diamond`（`PlayerResourceIds`）。**`updated_resources` を取り込む UseCase は無い**（login 以外の応答を読む機能が無かった。`.claude/api.md` の末節） | `home_presenter.gd`、`coin_amount.gd`、`diamond_total.gd` |
| h | `MstItemRepository` は `get_by_id` だけ（全件を返す口は無い）。`MstItem` は `deploy_key`・`id`・`type`・`name`。`mst_item` は同梱 DB に無く、配信があるときだけ引ける | `master_data/` |
| i | `ApiClient.request(method, endpoint, body, options)`。`options` の `idempotency_key` で `X-Unique-Request-Identifier` を付ける。401 は自動 refresh。失敗は `ApiResult.to_app_error()` → `AppError.Kind` | `core/data/http/api_client.gd` |
| j | `ErrorView.show_error(label, retry_button, error)` と `ErrorMessages.text(error)` が、エラーの文言と再試行ボタン（429 は待ち）の共通部品。`SESSION_EXPIRED` は agreement がメッセージを見せてからタイトルへ戻す | `core/presentation/`、`agreement_presenter.gd` |
| k | `SafeAreaMargins`（純粋関数）は `player/presentation/home/` にあり、ホームだけが使う。ログインボーナス画面は使っていない。**他コンテキストの presentation から参照できるのは domain/use_cases だけ**（依存チェック P2）なので、そのままでは使えない | `safe_area_margins.gd`、`tools/check_dependencies.py` |
| l | `debug/e2e_driver.gd` は、ログインボーナス画面で「出てから `ACTION_DELAY`（1.5 秒）＋ `--e2e-dwell` 秒後に画面中央をクリック」、写真は 1.0 秒後（`SHOT_DELAY`）。クリックは**マウスボタン**（タッチではない）。シーンは `scene_file_path` で分岐する | `debug/e2e_driver.gd` |
| m | アイコン資産は無い。`assets/` は `fonts`・`ui`（Kenney）・`video`。SVG は `icon.svg` だけ。自作資産の生成スクリプトは `tools/bg_video/` と `docs/ASSETS.md` の前例がある。`tools/` と `debug/` は製品の複製から除外、`assets/` は含める。`make check-release` は `preload` の実在を検査する（`%` を含む動的パスは対象外） | `docs/ASSETS.md`、`tools/prepare_release_project.py` |
| n | `HomeText.format_number`（桁区切り）が home の presentation にある。他コンテキストからは参照できない | `home_text.gd` |

## 1. 画面・シーン構成と遷移

### 1-1. 入口と遷移

ログインボーナス画面は**2 つの入口**で開く。同じ presenter・同じ部品で、入口だけが違う。

| 入口 | 開き方 | データの出どころ | 通信 | アニメーション | 戻り先 |
| --- | --- | --- | --- | --- | --- |
| login 直後（`FROM_LOGIN`） | 規約画面（または規約なし）の次。今と同じ位置（`goto_login_bonus()`） | login 応答（メモリの `LoginBonusRepository`） | **しない** | 「今回配った」段（`is_granted_now`）のマスだけ（K1） | ホーム |
| ホームから（`FROM_HOME`） | ホームの「ログインボーナス」ボタン（`goto_login_bonus_from_home()`） | `POST /login_bonus/list` を**開くたびに**呼んで取得（login 応答は古くなりうるので使わない。H2） | **する**（開いた直後に 1 回） | **しない**（確認のみ。H3）。再受け取りの応答を受けたときだけ VIP のマス | ホーム |

```
タイトル → 規約 → [ログインボーナス FROM_LOGIN] → ホーム ⇄ [ログインボーナス FROM_HOME] → ホーム
                          │ 受け取りボタン（再受け取り可のときだけ）     │ 同左
                          └ POST /login_bonus/receive → 同じ画面でスタンプ → タップでホーム
```

- **入口の渡し方**: `SceneRouter` は遷移の引数を持たず、オートロードに状態を置かない方針（architecture.md 2 節）なので、**入口ごとにシーンを分ける**。`login_bonus.tscn`（`FROM_LOGIN`。既定）と、それを継承した `login_bonus_from_home.tscn`（ルートの `@export var entry` だけ `FROM_HOME` に変える継承シーン）。`SceneRouter` に `LOGIN_BONUS_FROM_HOME_SCENE` と `goto_login_bonus_from_home()` を足す。`debug/e2e_driver.gd` は `scene_file_path` で分岐するので、2 つのパスを別々に扱える（11 節）
- **閉じる操作（H5）**: 画面の**ボタン以外**のどこをタップ（マウス左・タッチ）してもホームへ。受け取りボタンのタップは閉じない。**アニメーション中のタップは、最終状態へ飛ぶだけで閉じない**（K4）。完了後のタップで閉じる。連打しても二重に遷移しない（`_is_leaving`）。「閉じるボタン」は足さない
- **タップの受け方**: 今は `_input` で全イベントを拾うので、ボタンのタップも拾ってしまう。**`TapCatcher`（全画面の Control。`mouse_filter = STOP`）を背面に置き、その `gui_input` で受ける**。**規則: `TapCatcher` より前面にある、画面を覆うコンテナ・表示専用の Control（`Margin`・`Panel`・`VBox`・`calendar_section`・マス・ラベル・`ItemIcon`・`TextureRect` すべて）は `mouse_filter = IGNORE`**（`MarginContainer`・`PanelContainer` の既定は `STOP` なので、シーンを作るときに全部変える。1 つでも漏れるとその範囲のタップが閉じなくなる）。`STOP` にするのは受け取りボタン・再試行ボタンだけ。**例外**: 報酬の行を `ScrollContainer` にしたとき（縮め方③）は `STOP`（スクロールを受けるため。この範囲のタップは閉じない）。**受け取りボタンは受け取り中（無効化中）も `STOP` のまま**にする（二重タップがボタンを貫通して画面を閉じないため）。**受け取り中はタップで閉じない**（3-2 の 5 に合わせる）。テストで、シーン内の「`TapCatcher` より後ろの子孫」の `Control` を走査して、`Button`・`ScrollContainer` 以外は `IGNORE` を検査する（ルート・`BgVideo`・`TapCatcher` 自身は対象外。ルートは `STOP` でも `IGNORE` でもよい）。こうするとボタン上のタップは `TapCatcher` に届かない。マウス左とタッチ（`InputEventScreenTouch`）の両方を受け、二重に来ても `_is_leaving` で 1 回にする
- **ホームで再受け取りした後に戻ったとき**: ホームは `_ready` の `reload()` で PlayerRepository から作り直すので、所持数は 3-3 の取り込みだけで最新になる（ホーム側にイベント購読は足さない）
- 規約画面の前後の遷移・タイトルへの戻り（`SESSION_EXPIRED`）は変えない

### 1-2. シーン構成（`contexts/login/presentation/login_bonus/`）

```
LoginBonus (Control, login_bonus_presenter.gd)         … 入口 entry を @export
├─ BgVideo (VideoStreamPlayer)                          … 既存の背景動画
├─ TapCatcher (Control, 全画面, mouse_filter=STOP)       … 閉じるタップを受ける
└─ Margin (MarginContainer)                              … 安全領域の余白（1-4）
   └─ Panel (PanelContainer, 幅 800)                     … 既存の黄色いパネル（mouse_filter=IGNORE）
      └─ VBox
         ├─ TitleLabel                                   … 「ログインボーナス！」（星の行は 1-4 で外す）
         ├─ NoticeLabel                                  … 「本日のログインボーナスは受け取り済みです」（出す条件は 1-3）
         ├─ StatusLabel / RetryButton                    … FROM_HOME の読み込み中・失敗（1-5）
         ├─ NormalSection (calendar_section.tscn)        … 通常の段（null なら非表示）
         ├─ VipSection (calendar_section.tscn)           … VIP の段（null なら非表示）
         ├─ ReceiveButton                                … 再受け取りが可能なときだけ表示（VIP の段の下）
         ├─ RewardsHeader + RewardsList (VBox)           … 「今日配られた報酬」の行（reward_row.tscn の並び）
         ├─ TextFallbackLabel                            … 文字の画面（1-3 の「カレンダーを出さない」場合。今の BonusLabel）
         └─ TapLabel                                     … 「タップして続ける」
```

| 部品（シーン + スクリプト） | 責務 | 引数 |
| --- | --- | --- |
| `calendar_section.tscn`（`LoginBonusCalendarSection`） | 段 1 つ。見出し（「ログインボーナス」/「VIP ボーナス　VIP n」）と、行ごとの `HBoxContainer`（1 行 4 マス。最終日のマスは残りの幅を使う）にマスを並べる。行数は `loop_days` から決まる | `CalendarStageView`、マスの絵のサイズ（通常 80・VIP 72） |
| `calendar_cell.tscn`（`LoginBonusCalendarCell`） | マス 1 つ。「N 日目」・`ItemIcon`・数量・「＋n」・「今日」の印・縁取り・スタンプ（`TextureRect`）。状態は `apply_state(state, play)` で切り替える（`play = false` が最終状態へ飛ぶ入口。6 節。引数は常にこの 2 つに統一） | `CalendarCellView` |
| `reward_row.tscn`（`LoginBonusRewardRow`） | 「今日配られた報酬」の 1 行: `ItemIcon`（56）＋「名前 x数量」（名前の規則は今の `build_text` のまま） | `LoginBonusDisplay` |
| `stamp_player.gd`（`LoginBonusStampPlayer`、RefCounted） | スタンプのアニメーションの再生・即時完了。`Tween` はホストの Node から作る（6 節） | セル、開始の遅れ |
| `item_icon.tscn`（`ItemIcon`、`core/presentation/item_icon/`） | アイコンの共通部品（5 節）。ログインボーナス・ホームで共用 | `type`・`id`・`mst_item_type`・サイズ |

1 マスのノード数は、ルート 1＋「N 日目」ラベル・アイコン・数量ラベル・「＋n」ラベル・「今日」印・スタンプで 6〜7。14 マスで約 100 ノード（非機能「マスごとに数個」の範囲）。

### 1-3. 各状態の表示

**段（通常・VIP それぞれ）の状態**は、サーバーの 2 つの真偽（`is_granted_today`・`is_granted_now`）と最後に配った日数 `last_day` だけから決める。クライアントはゲーム内日付も `login_bonus_list` の空・非空も使わない（C8・T3）。

| 段の状態 | 条件（サーバーの値だけ） | マスの出し方 |
| --- | --- | --- |
| 今日の段 | `is_granted_today` が真、かつ `1 ≤ last_day ≤ loop_days` | `last_day` のマスが**今日**、それ以前が**受け取り済み**、それより後が**未来** |
| 今日の段でない | `is_granted_today` が偽（T2） | **全マスを同じ見た目**（強調なし・スタンプなし・未来の暗さも付けない）。段は隠さない |
| 日数が範囲外 | `is_granted_today` が真でも `last_day` が `loop_days` の範囲外（マスターで `loop_days` を縮めた直後。体験 9） | 「今日の段でない」と同じ（強調なし） |
| 段が無い | 応答の項目が null・欠落・型違い（T4・D3・D4） | その段を出さない |

**マス（1 日分）の状態**（`CalendarCellView.state`）:

| 状態 | 絵 | 数量・N 日目 | 縁取り・印 | スタンプ |
| --- | --- | --- | --- | --- |
| `TODAY`（今日。受け取り前のアニメーション直前を含む） | 通常の明るさ | 表示 | 色付きの太い縁取り＋「今日」の印。**アニメーションを再生しない再表示では最初から押印済み**（C7・C10） | `play_stamp` が偽なら押印済み、真ならアニメーション（6 節） |
| `RECEIVED`（今日より前） | 少し暗く（明るさ 0.8。C5） | 表示 | なし | 押印済み（アニメーションなし） |
| `FUTURE`（未来） | 彩度 0.5・明るさ 0.7（C6。目安） | 表示 | なし。鍵・ロックは付けない | なし |
| `NEUTRAL`（今日の段でない段・範囲外） | 通常 | 表示 | なし | なし |

- 「今日」の脈動（C4）は、**アニメーションを再生するマスの、スタンプが押される前**だけに限り、周期 1.2 秒・拡大 1.04 倍まで。押印後・再表示では止める（60fps の軽量化の第 1 段。7 節）。点滅はしない
- **VIP の段**: 通常と同じ部品。見出しは「VIP ボーナス　VIP n」（n はサーバーが返す対象レベル。受取済みの `vip_level` ではない。Q6・C8b）。マスの絵は 72
- **1 日に複数の報酬**: サーバーが返した順の先頭の絵に「＋n」（n = 件数 − 1。Q14）。並べ替えない（D2）
- **報酬の種別**（要件「報酬の種別ごとの表示」の表のとおり。絵の決め方は 5 節）: `unit`・`equipment`・`stamina`・`paid_diamond`・**未知の `type`** は `unknown` の絵＋数量で出す。**例外・空表示にしない**。報酬の行が 1 件も無い日（サーバーが不正な行を除いた結果。overview U-1）は、`unknown` の絵のみ・数量なしで出す
- **再表示の旨**（`NoticeLabel`）: **いずれかの段が今日の段で、どの段も `is_granted_now` が偽**のときだけ「本日のログインボーナスは受け取り済みです」をカレンダーの上に出す（T3・C10・H3・U-3 の既定案）。どの段も今日の段でない日には出さない。`FROM_HOME` の通常（確認のみ）は常にこの条件になる
- **「今日配られた報酬」の行**（C9）: `FROM_LOGIN` で `login_bonus_list` が非空のときだけ、その全行を（VIP・カムバックを含み、**受け取った順のまま**。D-4）。`FROM_HOME` では出さない。再受け取りの応答を受けたら、その報酬（VIP の段の今日の日の報酬）を行に足す（3-2）
- **受け取りボタン**（H4）: `ReceiveOffer.visible`（VIP の段の `can_re_receive` が真）のときだけ。押せない状態の印（灰色のボタンなど）は出さない。ラベルは「受け取る」（固定文字）
- **カレンダーを出さず今の文字の画面に落とす場合**: ① 両方の段が無い（T4・体験 7。VIP も通常も無い）② 旧サーバー（新キー無し。D4）③ いずれかの段の `loop_days` が 8 を超える、または 1 未満（C1。**画面全体**を文字にする。段ごとには落とさない）。文字の画面は今の `build_text` をそのまま使う（`login_bonus_list` が空なら「受け取り済み」の文）。②③ のときもカムバックの行は「今日配られた報酬」として文字に出る
- **「N 日目」「今日」「ログインボーナス」「VIP ボーナス」「＋n」「受け取る」の文字**: クライアントの固定文字（言語は `ja` 固定。overview 7 節 h）。名前はマスに出さない（C3）

### 1-4. レイアウトと安全領域

- パネル幅 800（今と同じ）。4 列: 1 マスの幅 = (800 − 左右の内側余白 2×24 − 列の間 3×12) ÷ 4 ≒ 179。通常 80・VIP 72 の絵が収まる。最終日のマスは行の残りの幅（`size_flags_stretch_ratio` = 空き列数＋1）。`loop_days` が 4 の倍数なら伸ばさない
- **縦の高さの見積り**（1920 基準。S5 で最大構成の写真で実測し、この表を直す）: 絵のサイズは次の項の確定値（通常 80・VIP 72・報酬の行 56）。内容の合計は、タイトル 72・再表示の旨 48・通常の段（見出し 40＋2 行×約 174）388・VIP の段（見出し 40＋2 行×約 150）340・受け取りボタン 112・今日配られた報酬（見出し 40＋最大 5 行×64）360・タップの案内 64・各部の間隔 8×16＝128 ＝ **約 1512**（絵を要件の目安 96/72 のままにすると 72＋48＋420＋340＋112＋440＋64＋128 ＝ 1624）。**ホームの既定の余白 `BASE_MARGIN_VERTICAL = 96`（上下で 192）は安全領域を含まない**（`home_presenter.gd` は安全領域の値を足している）。iPhone X の安全領域は上 44pt・下 34pt で、ビューポート単位（1080 単位 ÷ 375pt ≒ 2.88 倍/pt）では上 約 127・下 約 98（計 約 225。実機の値は `get_display_safe_area` で S5 に確かめる）。**余白 96 のままだと使える高さは 1920 − 192 − 225 ＝ 約 1503 で、1512 は収まらない**。この画面の基本の余白を**上下 48**（ホームの 96 でなく）にすると使える高さは 1920 − 96 − 225 ＝ **約 1599 で、1512 が収まる（余裕 約 87）**。つまり「**余白 48＋縮め方①②**」で収まる（どちらか片方では収まらない）。星の行（72）は外す。デスクトップ・シミュレーターは安全領域 0 でもっと余る
- **縮め方（余白 48 と①② は最初から適用済み。③ だけ実測で足りないときに足す）**: ① 「今日配られた報酬」の行の絵を要件の目安 72 → 56（1 行 −16、5 行で −80）② 通常のマスの絵を要件の目安 96 → 80（1 行 −16、2 行で −32）。**絵のサイズの確定値は通常 80・VIP 72・報酬の行 56**（要件の目安から縮めた旨はここだけに書く。他の箇所は確定値だけ） ③ 行が 6 件を超えるときだけ、報酬の行の領域を `ScrollContainer`（最大高さ固定）にする（Q2 の扱い）。①②③ はどれも要件の決定の範囲内
- **安全領域**: ログインボーナス画面も `SafeAreaMargins` を使う（モバイルのみ。デスクトップは 0）。使うために `SafeAreaMargins` を `contexts/player/presentation/home/` から **`core/presentation/safe_area_margins.gd`** へ移す（純粋関数でホームにしか依存しない。`HomePresenter` と `tests/unit/` の参照を直す。他コンテキストの presentation が `core/presentation` を使うのは規約の範囲）。基本の余白は `Margin` に足す（ホームと同じ方式）

### 1-5. FROM_HOME の読み込み・失敗の表示

1. 画面を開いた直後（`_ready`）は、`StatusLabel` に「読み込み中…」を出し、カレンダー・ボタン・行は隠す（背景動画とタイトルとタップの案内は出す）
2. 成功 → `StatusLabel` を隠して 1-3 の表示（アニメーションなし）
3. 失敗 → `ErrorView.show_error(StatusLabel, RetryButton, error)`（既存の共通部品）。再試行は同じ取得をやり直す。**失敗していてもタップでホームへ戻れる**（`TapCatcher` は常に有効）。`SESSION_EXPIRED` は agreement と同じく、メッセージを見せてタイトルへ戻す
4. 読み込み中・失敗中にホームへ戻っても、応答が来たときに画面（解放済み）を触らない（`_is_leaving` と `is_inside_tree()` を応答後に確認する）

## 2. スクリプトの分担と層

コンテキストは `login`（サーバーの `Domain/LoginBonus` と対応させる案は 12 節 Q-2。既定は**既存の `login` に置く**）。player と core・master_data への変更は最小。

### 2-1. 追加・変更するファイル

**`contexts/login/`**

| 層 | ファイル | 種別 | 責務 |
| --- | --- | --- | --- |
| domain/entities | `login_bonus_calendar.gd`（`LoginBonusCalendar`） | 追加 | 段 1 つの読み取りモデル: `mst_id`・`loop_days`・`last_day`（null は 0）・`is_granted_today`・`is_granted_now`・`can_re_receive`・`vip_level`（VIP のみ。無ければ 0）・`days: Array[LoginBonusCalendarDay]`。サーバーの項目に合わせ、判定は足さない。受け取り後の更新用に `duplicate_as_re_received()`（`is_granted_now = true`・`can_re_receive = false` の複製を返すだけ）を持つ |
| domain/entities | `login_bonus_calendar_day.gd` | 追加 | `day: int`、`rewards: Array[LoginBonus]`（`login_bonus_list` の要素と同じ型を使い回す。`unique_id` は空） |
| domain/entities | `login_bonus_calendars.gd` | 追加 | 通常・VIP の 2 段の束（`normal`・`vip`。null 可）。`has_any()` |
| domain/entities | `login_bonus_screen.gd` ほか表示用の値（`CalendarStageView`・`CalendarCellView`・`ReceiveOffer`） | 追加 | presenter が描くだけの値の束（1-3 の状態・`play_stamp`・絵の引数）。文字列は持たない |
| domain/entities | `login_bonus_display.gd` | 変更 | `item_type: String`（引けた `mst_item.type`。引けなければ空）を足す（アイコンのフォールバック ② に使う） |
| domain/entities | `login_data_result.gd` | 変更 | `login_bonus_calendars: LoginBonusCalendars` を末尾に足す（既定は空の束。既存の呼び出しを壊さない） |
| domain/repositories | `login_bonus_repository.gd` | 変更 | `replace_calendars(c)` / `calendars()` を足す（メモリの保持。`clear()` は両方を空にする）。**実装** `local_login_bonus_repository.gd` も同様 |
| domain/repositories | `login_bonus_calendar_repository.gd`（`LoginBonusCalendarRepository`） | 追加 | 契約（命名は既存の `login_repository` / `login_api_repository` の対に倣い、契約は `<名前>_repository`、実装は `<名前>_api_repository`。`remote` は master_data だけの呼び名で login には持ち込まない）（テストで偽物に差し替える）: `fetch_calendars()`・`receive_vip(mst_vip_login_bonus_id, idempotency_key)` |
| domain/use_cases | `fetch_login_bonus_calendars_use_case.gd` | 追加 | `FROM_HOME` の取得。`POST /login_bonus/list`。成功したらメモリの保持を置き換え、結果（`FetchLoginBonusCalendarsResult`）を返す。失敗は `Result.failure` 相当 |
| domain/use_cases | `receive_vip_login_bonus_use_case.gd` ＋ `receive_vip_login_bonus_result.gd` | 追加 | 再受け取り。`POST /login_bonus/receive`。成功なら player の公開 UseCase で所持数を反映（3-3）→ メモリの VIP の段を `duplicate_as_re_received()` に置き換え → 受け取った報酬（VIP の段の `last_day` の日の報酬）を結果に載せる |
| domain/use_cases | `get_login_bonus_screen_use_case.gd` | 追加 | 同期。メモリの保持と `login_bonus_list` から `LoginBonusScreen` を作る（1-3 の規則。名前・`mst_item.type` の引きは既存 `GetLoginBonusDisplaysUseCase` を使う）。`FROM_LOGIN` / `FROM_HOME` の違いは引数 `include_login_bonus_list` と `play_stamp_allowed` で受ける |
| domain/use_cases | `get_login_bonus_displays_use_case.gd` | 変更 | `item_type` を載せる。`unit`・`equipment`・`stamina` 以外の行で `mst_item` を引く（`item_type` のため。`item_name` は今のまま `item` の行だけ） |
| domain/use_cases | `login_use_case.gd` | 変更 | 成功時に `login_bonus_calendars` もメモリへ置く（`replace_calendars`）。再受け取りの応答は login ではないので扱わない |
| data/api | `login_bonus_calendar_response.gd` | 追加 | **段 1 つ**の辞書 → `LoginBonusCalendar`（login 応答と list 応答で共用。4 節） |
| data/api | `login_bonus_calendars_response.gd` | 追加 | list 応答（通常・VIP の 2 キー）→ `LoginBonusCalendars` |
| data/api | `receive_vip_login_bonus_response.gd` | 追加 | 再受け取りの応答（`updated_resources`・`trx_vip_login_bonus`）の取り出し |
| data/api | `login_response.gd` | 変更 | 新しい 2 キーを `LoginBonusCalendarResponse` で読み、`to_domain()` に載せる。既存の項目・`login_bonus_list` は変えない |
| data/repositories | `login_bonus_calendar_api_repository.gd` | 追加 | 契約の実装。`ApiClient.request("POST", "/login_bonus/list", {})`（冪等キーなし）と `"POST", "/login_bonus/receive", {mst_vip_login_bonus_id}`（冪等キーつき）。`ApiResult` を `AppError` に直して返す |
| presentation | `login_bonus/login_bonus_presenter.gd`・`login_bonus.tscn` | 変更 | 入口の分岐・描画・受け取りボタン・タップ。業務の判断はしない（UseCase の結果を描く） |
| presentation | `login_bonus/login_bonus_from_home.tscn` | 追加 | 継承シーン（`entry = FROM_HOME`） |
| presentation | `login_bonus/calendar_section.{tscn,gd}`・`calendar_cell.{tscn,gd}`・`reward_row.{tscn,gd}`・`stamp_player.gd`・`calendar_text.gd` | 追加 | 1-2 の表。`calendar_text.gd` は「N 日目」「＋n」などの文字を作る静的関数（`NumberText` を使う） |

**`contexts/player/`**（所持数の反映。他コンテキストは公開 UseCase だけ使う）

| 層 | ファイル | 種別 | 責務 |
| --- | --- | --- | --- |
| domain/use_cases | `apply_updated_resources_use_case.gd` | 追加 | `updated_resources` を PlayerRepository の現在値へ取り込む（3-3）。失敗しない（メモリのみ）。`ApplyLoginDataUseCase` と同じ形（`Result` を返す） |
| presentation | `home/home_presenter.gd`・`home.tscn` | 変更 | 「ログインボーナス」ボタン（`NavRow`）の接続（`setup` にルーターを足す）。値の横の `ItemIcon` 3 つ（5-5）。ラベルのパスが変わる（3 つの値ラベルが `ValueRow` の子になる） |
| presentation | `home/safe_area_margins.gd` | 移動 | `core/presentation/safe_area_margins.gd` へ（1-4） |

**`core/`**

| 層 | ファイル | 種別 | 責務 |
| --- | --- | --- | --- |
| domain | `item_icon_resolver.gd`（`ItemIconResolver`） | 追加 | 純粋関数。`type`・`id`・`mst_item_type`・「その絵が存在するか」の述語（Callable）から、絵のキー（`items/<id>`・`fallback/category_<type>`・`fallback/unknown`）を返す（5-2） |
| presentation | `item_icon/item_icon.{tscn,gd}`（`ItemIcon`） | 追加 | `TextureRect`。`setup(type, id, mst_item_type, size)` で絵を出す。読み込みは `ItemIconTable` から（動的な `load` をしない） |
| presentation | `item_icon/item_icon_table.gd`（`ItemIconTable`） | 追加（**生成物**） | キー → `preload` した `Texture2D` の定数表と `has_key`・`texture_of`。生成スクリプトが作る（5-3） |
| presentation | `number_text.gd`（`NumberText`） | 追加 | 桁区切り（`HomeText.format_number` と同じ規則）。`HomeText` を寄せる整理は任意（S5 で小さく） |
| presentation | `safe_area_margins.gd` | 移動 | 上のとおり |

**`app/`**: `app_context.gd` に UseCase の取得メソッド（`fetch_login_bonus_calendars_use_case()`・`receive_vip_login_bonus_use_case()`・`get_login_bonus_screen_use_case()`・`apply_updated_resources_use_case()`）と、`LoginBonusCalendarApiRepository` の組み立てを足す。`scene_router.gd` に `LOGIN_BONUS_FROM_HOME_SCENE`・`goto_login_bonus_from_home()` を足す。**EventBus への影響なし**（`session_expired` の購読は既存の `_login_bonus_repository.clear()` が新しい保持も空にする）。

**`master_data/`**: 変更なし（`MstItemRepository.get_by_id` を使う。全件取得は足さない。5-6）。

**`debug/`・`tools/`・`assets/`**: 5・11 節。

### 2-2. 層の確認（依存チェックに通ること）

- presenter（presentation）は UseCase と `core/presentation` の部品（`ItemIcon`・`ErrorView`・`SafeAreaMargins`・`NumberText`）だけを使う。data（`*_response.gd`・Repository 実装）は参照しない（P1）。ホームは `login` の UseCase を使わない（遷移だけ）
- `login` → `player` は `ApplyUpdatedResourcesUseCase`（公開 UseCase）だけ（X1・P2）
- `core/domain/item_icon_resolver.gd` は `Node`/`Texture2D` に依存しない（D2）。`core/presentation/item_icon_table.gd` がアセットを `preload` する（C1: core は contexts・master_data を参照しない。引けた `mst_item.type` は呼び出し側が渡す）
- `debug/` の確認用画面は本番コードから参照されない（T1）。製品の複製から除外される

### 2-3. オートロードへの影響

追加なし。`AppContext`（取得メソッド・組み立て）と `SceneRouter`（遷移 2 つ）の追記だけ。`_ready` で他のオートロードを呼ばない規則は守る。

## 3. API 呼び出し

**項目名はすべて overview の名前での仮置き**（S2 のマージ後に差分を直す）。パスは overview のとおり、どちらも POST。

### 3-1. 一覧

| API | 呼ぶタイミング・呼び元 | 送る値 | 冪等キー | 応答の使い方 |
| --- | --- | --- | --- | --- |
| POST `/auth/login`（既存） | タイトルの LOGIN 段階（変更なし） | なし | 付ける（既存） | 末尾に追加された 2 キー（通常用・VIP 用。仮に `login_bonus_calendar`・`vip_login_bonus_calendar`）を読む（4 節）。`login_bonus_list` は今のまま |
| POST `/login_bonus/list`（新） | `FROM_HOME` で画面を開いた直後に 1 回（`FetchLoginBonusCalendarsUseCase`）。再受け取りのエラーの後の取り直しにも使う | `{}` | **付けない**（任意。毎回最新が要るので再利用の意味が無い。再送は同じ呼び出しのやり直し） | 通常用・VIP 用（login の新キーと同じ形。`is_granted_now` は常に偽）を `LoginBonusCalendars` に |
| POST `/login_bonus/receive`（新） | 受け取りボタンのタップ（`ReceiveVipLoginBonusUseCase`） | `mst_vip_login_bonus_id`（VIP の段の `mst_id`） | **付ける**（presenter が `_receive_key` に保持。3-4） | `updated_resources` を所持数へ、`trx_vip_login_bonus` から日数・`vip_level` を取り出して VIP の段を更新（3-3・4 節） |

### 3-2. タイミングと失敗時

**FROM_LOGIN**: 通信しない。`_ready` で `GetLoginBonusScreenUseCase.handle()`（メモリ）→ 描画 → アニメーション開始（6 節）。

**FROM_HOME**: `_ready` で取得（1-5 の読み込み中表示）→ 描画（アニメーションなし）。

**受け取りボタン**（`FROM_LOGIN`・`FROM_HOME` 共通）:

1. タップ → ボタンを無効化して「受け取り中…」にする（**二重タップの防止**。応答が戻るまで再度押せない）。`_receive_key` が空なら作る
2. `await receive_vip_login_bonus.handle(mst_id, _receive_key)`
3. **成功**: メモリが更新済み。`GetLoginBonusScreenUseCase` で画面の値を作り直して描画し、VIP の今日のマスに**スタンプのアニメーション**（T5・K1。6 節）。ボタンは消す。「今日配られた報酬」の行には、受け取った報酬を足す（`FROM_LOGIN` は既存の行の後ろ、`FROM_HOME` は行が無いので新しく出す。12 節 Q-3）。再受け取りの旨の `NoticeLabel` は、VIP の段が `is_granted_now` なので出ない。`_receive_key` を空に戻す
4. **失敗**: `AppError.kind` で分ける。
   - `BUSINESS`（日をまたいだ・既に受け取り済み・条件を満たさないなど、サーバーが「いまは受け取れない」と返した）: **状態を取り直す**（`FetchLoginBonusCalendarsUseCase`）→ 画面を更新（アニメーションなし。ボタンは取得結果で出し直し）→ 短いメッセージ（Toast「状態を更新しました」）。`_receive_key` は作り直す（業務エラーは同じキーで再送しても同じエラーが返り続ける。3-4）
   - `NETWORK`・`SERVER_BUSY`・`CONFLICT`・`SERVER_ERROR` など再試行できるもの: ボタンの下に `ErrorMessages.text(error)` を出し、ボタンを有効に戻す。再タップは**同じ `_receive_key`** で送る（`IdempotencyKey.can_reuse`。サーバーが先に処理していても同じ応答が返る）
   - `RATE_LIMITED`: `ErrorView` の待ち（`retry_after` の間ボタンを無効）
   - `SESSION_EXPIRED`: メッセージを見せてタイトルへ（agreement と同じ）
   - `MAINTENANCE`: メンテナンスの文言（`ErrorMessages`）
5. 受け取り中に画面を離れた（ホームへ戻った）場合も、応答後に画面を触らない（1-5 の 4）。**受け取り中は、タップで閉じない**（`_is_receiving` の間は `TapCatcher` の閉じる処理を無効にする。ボタンの二重タップが画面を閉じて所持数の反映前にホームへ戻るのを防ぐ）。通信は `ApiClient` のタイムアウトで終わり、失敗の表示のあとは閉じられる

**取り直しに失敗**したとき（BUSINESS の後の list も失敗）: 今の画面の表示は維持し、ボタンを消してエラー文を出す（古い状態でボタンを押させない）。

### 3-3. `updated_resources` をホームの所持数へ反映する（Q31）

- **現状**: 取り込む UseCase が無い（0 節 g）。**`ApplyUpdatedResourcesUseCase`（player の公開 UseCase）を足す**。`ReceiveVipLoginBonusUseCase` が呼ぶ
- **取り込む範囲**: ホームが読む 3 種だけ。**他のキーは無視する**（読む画面が無い。足すときは各機能が拡張）
  - `trx_item_list`: 行の `mst_item_id` を主キーに**差し替え**（無ければ追加）。変更のあった行だけが載りうるので全置き換えにしない（`.claude/api.md` の前提）。コイン・無償ダイヤ・経験値アイテムなどが入る
  - `trx_diamond`: 単数のオブジェクト。キーがあれば置き換える（再受け取りの報酬には有償ダイヤは無いはずだが、来たら取り込む）
  - `trx_stamina_list`: キーがあれば、行の `mst_stamina_type`（仮。S2 で確認）を主キーに差し替える
  - `trx_wallet_list`・`trx_unit_list`・`trx_equipment_list`: 今のホームが読まないので取り込まない
- **削除行**: `is_delete` は `PlayerState.is_row_deleted()` で読む（既存の規則）。差し替えの行をそのまま入れ、表示側（`CoinAmount` など）の既存の除外に任せる
- **サーバーの時刻差**: 再受け取りの応答の `Date` でオフセットは更新しない（login のときだけ）
- **PlayerRepository**: `current()` が返す `PlayerState` の `trx_lists` を直接書き換えず、新しい `PlayerState` を作って `replace()`（全量の置き換えの契約を保つ）
- 反映のタイミングは UseCase 内（応答の直後）。ホームは戻ったときの `_ready` で読む。ホームが開いたままのときは無い（ログインボーナス画面はシーンの切り替えで開くので、ホームは常に作り直される）
- `.claude/api.md` の末節（「今は読まない」）をこの機能の実装に合わせて書き換える（10 節）

### 3-4. 冪等キー

- 受け取り API だけ付ける。**キーの寿命は「ひとつの操作」**（title-to-home 3-4 と同じ）。presenter が `_receive_key` に持ち、`IdempotencyKey.generate()` で作る
- 通信断・409・503 の再送は同じキー。業務エラー（299）の後と成功の後は作り直す（`IdempotencyKey.can_reuse(error.kind)`）
- 状態の取得（list）には付けない（上の表）。ヘッダーの `X-Master-Hash`・`X-Platform`・`Accept-Language` は `ApiClient` が付ける（変更なし）

## 4. Response からモデルへの対応と null の扱い

**項目名は overview の仮置き**。`unique_id` を全日の報酬に入れるか・`days` の形は S2 で確定（12 節の「S2 マージ後の差分」）。ここでは次の形を仮定する:

```
<段> = { mst_id, loop_days, last_day|null, is_granted_today, is_granted_now,
         can_re_receive（VIP のみ）, vip_level（VIP のみ）,
         days: [ { day, rewards: [ {type, id, amount, metadata} ... ] } ... ] }
login 応答:   末尾に 2 キー（通常用 / VIP 用。各 <段> か null）
list 応答:    同じ 2 キー
receive 応答: { updated_resources: {...}, trx_vip_login_bonus: { day, vip_level, mst_vip_login_bonus_id, received_at ... } }
```

| 応答の項目 | モデル（domain） | null・欠落・型違いの扱い（D3 の規則を `data/api` に閉じ込める） |
| --- | --- | --- |
| 段のキー（通常用・VIP 用） | `LoginBonusCalendars.normal` / `.vip` | キーが無い・null・Dictionary でない → **null**（その段を出さない。旧応答でもここに落ちる）。両方 null かつ `login_bonus_list` が空 → 今の「受け取り済み」の文字画面 |
| `mst_id` | `LoginBonusCalendar.mst_id` | 文字列。無い・null → 空文字。VIP で空のときは `can_re_receive` を偽に落とす（ボタンを出さない。送る ID が無いため） |
| `loop_days` | `.loop_days` | `int()`。無い・null・数値でない → 0。**0 以下・8 超は 1-3 のとおり文字の画面へ落とす条件** |
| `last_day` | `.last_day` | null・無い → 0（まだ配っていない）。`int()` |
| `is_granted_today` / `is_granted_now` / `can_re_receive` | 同名 | **真偽値型のときだけその値。それ以外（null・無い・0/1・文字列）は偽**（安全側。ボタンもアニメーションも出さない）。`can_re_receive` は VIP のみ。通常に付いていても無視 |
| `vip_level` | `.vip_level` | `int()`。無い・null → 0（見出しは「VIP ボーナス」のみ） |
| `days` | `Array[LoginBonusCalendarDay]` | Dictionary 以外の要素は捨てる。`day` が 1〜`loop_days` の範囲外・重複は捨てる（先勝ち）。`1..loop_days` のうち欠けた日は**空の日**（報酬なし。`unknown` の絵のみ）として補う（マスを欠けさせない）。並びは `day` 昇順に整える（日の並びは番号で決まるので、並べ替えにあたらない。**日の中の報酬の順は受け取ったまま**） |
| `rewards`（要素） | `LoginBonus`（`unique_id` は空） | `type`・`id` は `str()`（無い・null → 空文字）、`amount` は `int()`（無い → 0）、`metadata` は `JsonReader.get_dict`（null → `{}`）。`type` が空の行は捨てる（絵も名前も決められない）。**未知の `type` は捨てない**（`unknown` の絵で出す） |
| `login_bonus_list`（既存） | `LoginBonus` | 変更なし（`LoginResponse._to_login_bonus`） |
| receive の `updated_resources` | `ApplyUpdatedResourcesUseCase` の入力（辞書のまま） | 無い・null・Dictionary でない → `{}`（取り込みなし）。3 種のキーは配列/辞書の型を確かめ、違えば無視 |
| receive の `trx_vip_login_bonus` | `ReceiveVipLoginBonusResult.vip_day`（`int`）・`.vip_level`（`int`） | 無い・null → 0。**VIP の段の `last_day` はこの値で更新する**（据え置きなので変わらないはずだが、サーバーの値を正とする）。0 のときは更新しない（取れない値で壊さない） |

- 変換のクラスは `LoginResponse`（login 応答）と `LoginBonusCalendarsResponse`（list 応答）が、段 1 つを `LoginBonusCalendarResponse.from_dict()` に任せる。**2 通りの変換を作らない**（形は同じ）
- 画面（presenter）は `LoginBonusScreen` だけを見る。生の Dictionary を domain・presentation に渡さない（architecture.md の腐敗防止層）

## 5. アイコン・アセット

### 5-1. 置き場と規格（I1〜I8）

| 項目 | 決定 |
| --- | --- |
| 置き場 | `assets/icons/items/<mst_item.id>.svg`（`mst_item` 全行。IDs はサーバーの `MstItemSeeder` の 29 行から転記）、`assets/icons/fallback/category_<mst_item.type>.svg`（9 種）・`fallback/unknown.svg`、`assets/icons/ui/stamp_check.svg`（スタンプ） |
| 規格 | ビューボックス 128×128、余白 8、背景透明、最小の線の太さ 4（128 基準）以上、太い輪郭線なし、角丸・柔らかい影・ごく控えめなグラデーション。色は夜空（青紫系）に合わせた限定パレット 1 つを全アイコンで共通。色だけで意味を伝えない（形も変える。I7・I8） |
| import | SVG の既定（スケール 1.0）。表示は 80（通常のマス）・72（VIP のマス）・56（報酬の行）・48（ホーム）なので 128 のラスターで足りる。S5 で import の設定（`.import`）はリポジトリに入れる |
| 数 | 29＋10＋1 = 約 40 |

### 5-2. 引き方（I5・I9）

- `ItemIconResolver.resolve_key(type, id, mst_item_type, exists)`（core/domain の純粋関数）:
  1. `exists("items/" + id)` → `items/<id>`（`id` が空のときは飛ばす）
  2. `mst_item_type` が空でなく `exists("fallback/category_" + mst_item_type)` → `fallback/category_<type>`
  3. それ以外 → `fallback/unknown`
  - **`type` が `unit`・`equipment`・`stamina`・`paid_diamond`・未知の値のときは 1・2 を飛ばして 3**（枠のアイコンは対象外・I11。`stamina` は `mst_item` の行ではない。Q4）。wallet 系・`item` は `id` で引く（要件の表）
  - どの段でも例外・空表示にしない。マスターが無くても 1・3 は動く（`mst_item_type` は空で渡るだけ）
- **`mst_item_type` の出どころ**: ログインボーナスでは `GetLoginBonusDisplaysUseCase` とカレンダーの表示値の作成（`GetLoginBonusScreenUseCase`）が `MstItemRepository.get_by_id(id).type` を引いて渡す（`unit`・`equipment`・`stamina` は引かない）。**マスターが引けなければ空**。ホームは固定の 3 つ（5-5）で `items/` が必ず在るので渡さない。**引きは画面を開くとき 1 回だけ**（`master_data_loaded` は購読しない。非機能）
- `ItemIcon.setup(...)` が `ItemIconResolver` に `ItemIconTable.has_key` を渡し、`ItemIconTable.texture_of(key)` を `texture` に入れる。`mst_item` を引かない・`master_data` を参照しない（C1）

### 5-3. 動的パスを使わない（U-5 の既定案）

`"res://assets/icons/%s.svg" % id` の動的な `load` は、書き出し（実機ビルド）に入るかが未確認（要件 F）で、`make check-release` も `%` を含む参照は検査しない。**生成スクリプトが `item_icon_table.gd`（キー → `preload("res://assets/icons/…")` の定数辞書）を作り、`ItemIcon` はそこだけから読む**。利点: ① `preload` の実在が `make check-release` で検査される ② 書き出しの設定に依存しない ③ ID に無いキーは `has_key` が偽で、フォールバックへ落ちる。実機の書き出しは別の確認（本機能の確認は複製の起動検査まで）。

### 5-4. 生成スクリプトと ASSETS.md（I1・I7）

- `tools/icons/generate_icons.py`（**標準ライブラリだけ**。乱数を使わない・使うなら種を固定。実行は何度でも同じ出力）: 図形のテンプレート（回復の瓶・ブースト・経験値の結晶・素材・通貨のコイン・ダイヤ・スタミナ・資源・ポイントのバッジなど。カテゴリごとに共通の形）と、ID ごとの差分の表（色・中身の量・小さな印の数）から、全 SVG と `item_icon_table.gd` を出力する
- 実行: `python3 tools/icons/generate_icons.py`（`make icons` として登録）。**検査**: `make check-icons`（生成して git の差分が出ないこと、各 SVG が規格を満たすこと〔viewBox・サイズ上限・禁止要素〕、表のキーと実在の一致）。`make check` に足す（実行が軽い。12 節 Q-4 の仮置き）
- `docs/ASSETS.md` に「アイコン（自作）」の節を足す: 規格（5-1）・引き方（5-2）・生成と検査の手順・**`mst_item` に行が増えたとき**（`tools/icons/` の差分の表に 1 行足して再生成。足し忘れてもフォールバックで出るので画面は壊れない）・容量の実測値（5-6）。`THIRD_PARTY_NOTICES.md` は変えない（自作）
- 先に**比較用の 3 点**（例: `free_diamond`・`gold`・`unknown`）だけ作り、画風と import 後の見た目・容量を確かめてから全点へ（要件の段取り）

### 5-5. ホームの値の横の絵（I10・D-1・Q11）

- 3 つの値ラベルを `HBoxContainer`（`ValueRow`）で包み、左に `ItemIcon`（48）を置く: コイン → `coin`、ダイヤ → `free_diamond`（**合計用の絵は作らない**。D-1）、スタミナ → `stamina_50`。値ラベルの位置は右にずれるだけで、パネルの大きさ・他の見た目は変えない
- ホームは `master_data` を使わず固定 ID で出す（`PlayerResourceIds` の `COIN`・`FREE_DIAMOND` と、スタミナ用の定数を足す）。ラベルの `@onready` パスと `home_presenter_test.gd` の参照を直す

### 5-6. 確認用の一覧画面（I12）と容量（R4）

- `debug/icon_gallery.tscn`（製品に入らない）: `ItemIconTable` の全キーを並べ、`MstItemRepository` を持てるときは**マスターに在って絵が無い ID**を赤く出す（全件を返す口が無いので、ギャラリーは `master.db` を読む debug 専用の読み取りを持つ。`master_data/` は変えない）。`--e2e-shot` で 1 枚に撮る
- **APK 容量の実測（R4）**: ① 比較用 3 点を作った時点 ② 全 40 点を作った時点の 2 回、(a) SVG ファイルの合計（`du`）、(b) import 後の `.godot/imported/` の該当 `.ctex` の合計、(c) `make release-project` した複製を `--export-pack` で pck にしたときのサイズ差（アイコンあり・なし。pck は書き出しテンプレート無しで作れる想定。作れなければ (b) を代用）を測る。基準は**アイコン全体 1MB 以内（目安）かつ背景動画（約 2MB）を超えない**。超えるときは SVG の import スケール・図形の数を見直す。結果は PR 本文と `docs/ASSETS.md` に書く

## 6. スタンプのアニメーション（K1〜K6）

**入口は 1 つ**: `LoginBonusCalendarCell.apply_state(state, play)`。`play = false` なら最終状態（押印済み・縁取りの強調）へ**即時**に飛ぶ。再表示・過去のマス・`FROM_HOME` はこの入口を最初から `play = false` で使う（K6。将来の「アニメーションを減らす設定」はここで`play` を偽にするだけで足りる）。

**再生するマス**（K1）: `CalendarCellView.play_stamp = true` のマスだけ。値は `GetLoginBonusScreenUseCase` が「その段が今日の段、かつ `is_granted_now` が真、かつ今日のマス」から作る。`FROM_HOME` の最初の描画では常に偽。

| 項目 | 値（要件の目安を確定） |
| --- | --- |
| スタンプの絵 | `assets/icons/ui/stamp_check.svg`: 赤橙（#E0483A 付近）の二重の円の印（外周の輪＋内側の輪）に白いチェック。**形（円＋チェック）で受け取り済みと分かる**（色だけに頼らない）。 マスの 7〜8 割を覆う |
| 動き | 初期: スケール 2.0・透明度 0・位置はマスの中心。`Tween` で、スケール 2.0 → 1.0（`TRANS_BACK`・`EASE_OUT`。Godot の既定の overshoot で、着地で少し行き過ぎて戻る＝弾み）、透明度 0 → 1 は最初の 0.1 秒。使う動きは**位置・スケール・透明度だけ**（K5。シェーダ・パーティクルなし） |
| 時間 | **通常の段: 開始 0.3 秒（画面が出てから）・スタンプ 0.4 秒（着地 0.7 秒）**。**VIP の段: 開始 0.5 秒・0.4 秒（着地 0.9 秒）**。着地で**マスが明るくなる**（`modulate` の明るさを 1.0 → 1.3 → 1.0。**全体で 0.1 秒**）。どちらも 1.0 秒以内に最終状態（通常 0.8 秒・VIP 1.0 秒。K3）。両段を再生しない場合（片方だけ）は、その段の開始のまま |
| 再受け取り（`FROM_*` 共通） | 画面は既に出ているので、**応答を受けた瞬間に VIP の今日のマスのスタンプを一度外して（透明度 0）、0.3 秒後に同じ動きで押す**（着地 0.7 秒、全体 0.8 秒）。「受け取った感」を出すため（既に押印済みの絵の上に重ねるだけだと変化が分からない。12 節 Q-5 の仮置き） |
| 点滅 | 3 回/秒を超えない。「今日」の脈動は押印前だけ（周期 1.2 秒・1.04 倍）で、スタンプが始まったら止める |
| タイミングの基準 | 「画面が出て」= `_ready` の描画完了の次のフレーム。`Tween` はホスト（presenter）から作り、画面を離れたら kill する |
| スキップ（K4） | アニメーション中のタップは、実行中の Tween をすべて完了状態へ（`Tween.custom_step` か、`kill()` ののち各マスの `apply_state(state, false)`）で**最終状態へ飛ぶだけ**で、閉じない。完了後のタップでホームへ |
| e2e との関係 | 中央クリック（出てから 1.5 秒＋dwell）は完了後。写真（1.0 秒後）は VIP の演出の終了と同時刻になるので、**ログインボーナス画面の写真は 1.2 秒後に撮る**（`SHOT_DELAY` をこの画面だけ変える。11 節）。録画は 30fps 固定で、押印の動きが約 20 コマに写る |

## 7. 60fps（R2）の実測と方針

**基準**: iPhone X（A11）、背景動画（1080×1920）の再生中に、最大 14 マス（通常 7＋VIP 7）とスタンプで 60fps（フレーム 16.6ms）。動画では測れない（Movie Maker は固定フレーム）。

**実行形態**: `Performance` の描画統計（ドロー呼び出し・オブジェクト数）はヘッドレスでは取れない（描画しない）ので、`frame_probe.gd` は**ヘッドレスでない通常の起動**（ウィンドウあり。`--write-movie` は固定フレームで時間が歪むので併用しない）で動かす。

**制約**: 製品ビルドの書き出しテンプレートは手元に無い（CLAUDE.md の「未確認」）ので、**実機（iPhone X）での計測はこの環境ではできない**。実機計測は未解決（12 節 Q-6）。代わりに次の 2 段で見る。

1. **現行の画面の基準値（V2 の最初の作業）**: 現行のログインボーナス画面とホームを、**デバイス非依存の指標**で測る。`debug/frame_probe.gd`（debug 専用。`--e2e-frame-probe=<秒>` で、画面が出てから指定秒の `Performance` の値を記録して出力）で、`TIME_PROCESS`（ms）・`RENDER_TOTAL_DRAW_CALLS_IN_FRAME`・`RENDER_TOTAL_OBJECTS_IN_FRAME`・ノード数（`OBJECT_NODE_COUNT`）を、画面が出てから 2 秒間の平均・最大で出す。開発機の値は絶対値としては使わず、**変更前後の比**とドロー呼び出し数・オブジェクト数（端末に依らない）で比べる
2. **変更後**: 同じ手順で、最大構成（通常 7＋VIP 7＋報酬 5 行）を測る。**ドロー呼び出し数・オブジェクト数が基準の何倍か**と、`TIME_PROCESS` の比を PR に書く。実機が使えるとき（誰かが書き出せたとき）は、Godot の Monitor（フレーム時間）で同じ 2 秒を測る

**軽くする順**（overview 5 節。要件の見た目の決定は変えない）: ① 「今日」の脈動を止める（最初から 1-3 のとおり押印前だけ） ② VIP のスタンプの開始のずらし幅・同時再生を減らす ③ マスの装飾（影・グラデーション）を事前に作った絵（SVG の中）に置き換える。**マスに `PanelContainer` ＋ `StyleBoxFlat` の影を使わない**（影・角丸は SVG の絵の側）を最初の設計から守る

## 8. スライス

サーバーの S2（設計）・S3（実装）は別の流れ。**V2 はサーバーに依存しない**ので先に出せる。V3 はサーバーの新キー・新 API が必要。

### V2: アイコン・共通部品（サーバー不要）

| 内容 | ファイル |
| --- | --- |
| 基準の実測（R2）の仕組みと、現行の値 | `debug/frame_probe.gd`、E2E の引数（11 節） |
| アイコン一式の生成と検査 | `tools/icons/`、`assets/icons/**`、`core/presentation/item_icon/item_icon_table.gd`（生成）、`Makefile`（`icons`・`check-icons`） |
| 共通部品 | `core/domain/item_icon_resolver.gd`、`core/presentation/item_icon/item_icon.{tscn,gd}`、`core/presentation/number_text.gd` |
| ホームの値の横の絵 | `home.tscn`・`home_presenter.gd`、`PlayerResourceIds`（スタミナ用の定数） |
| 確認用の画面 | `debug/icon_gallery.tscn` |
| 容量の実測（R4）、ASSETS.md | `docs/ASSETS.md`、PR 本文 |
| テスト | 9 節の V2 |

### V3: 導線・カレンダー・スタンプ・再受け取り（サーバーの S3 が必要）

| 内容 | ファイル |
| --- | --- |
| login 応答の新キー・list・receive の通信とモデル | 2-1 の login の domain・data（`LoginBonusCalendar*`・`*Response`・`LoginBonusCalendarApiRepository`・UseCase 3 つ）、`ApplyUpdatedResourcesUseCase`、`AppContext` |
| 画面（カレンダー・スタンプ・受け取りボタン・2 つの入口） | login の presentation 一式、`SafeAreaMargins` の移動、`SceneRouter` |
| ホームの導線（ボタン） | `home.tscn`・`home_presenter.gd` |
| e2e（ホームから開く・再受け取り・旧応答） | `debug/e2e_driver.gd` |
| 既存テストの更新 | `login_bonus_presenter_test`・`login_response_test`・`login_use_case_test` ほか（9 節） |
| ドキュメント | 10 節 |
| 60fps の変更後の実測 | 7 節 |

V3 の前に S2 のマージ後の差分を直す（12 節）。V2 と V3 は別の PR・別の会話に分ける（`docs/<機能>-client-v2` など。ブランチ名は実装時に決める）。

## 9. テスト（GdUnit4。`make check-quiet` を通す）

「前提 → 操作 → 期待」をテストごとに書く（coding-standards の規約 7）。偽物の Repository は `tests/unit/contexts/login/domain/fake_login_repositories.gd` に足す。

**V2**
- `ItemIconResolver`: `items/<id>` が在る → そのキー。無い＋`mst_item_type` あり → `category_*`。両方無い → `unknown`。`type` が `unit`・`equipment`・`stamina`・`paid_diamond`・未知 → `unknown`（`items/` に同じ ID があっても引かない）。`id` が空 → `unknown`。述語が全て偽 → 常に `unknown`（空にならない）
- `ItemIconTable`: 生成物の全キーが `has_key` で真・`texture_of` が `null` でない（`preload` の実在）。`fallback/unknown` と `ui/stamp_check` が必ず在る
- `ItemIcon`: `setup` で `texture` が入る・存在しない ID でもエラー・空表示にならない（シーンを作るテスト）
- `NumberText`: 20000 → `20,000`、0、負、3 桁の境界（`HomeText.format_number` と同じ結果）
- `tools/` の生成の検査（`make check-icons` の単体テスト: 規格違反の SVG を弾く・表と実在の不一致を弾く）
- ホームの presenter: 3 つの `ItemIcon` が在り、値ラベルの文字が従来と同じ（パスの変更に追従）。ボタン（V3）は含めない

**V3**
- `LoginBonusCalendarResponse`: 正常な段・null・キー無し・Dictionary でない・`loop_days` 0/負/文字列・`last_day` null・真偽値が null/0/1/文字列（偽に落ちる）・`days` の欠け/重複/範囲外/不正な要素・報酬の `type` 空（捨てる）と未知の `type`（残す）・`metadata` null
- `LoginResponse`: 新キー無しの旧応答で `login_bonus_calendars` が空、`login_bonus_list` は従来どおり。新キーがあっても既存の項目は変わらない
- `GetLoginBonusScreenUseCase`（**中核。表の全行**）: 今日の段（`last_day` = 1・中間・`loop_days`）・今日の段でない・`is_granted_today` が真で `last_day` が範囲外・`is_granted_now` が真/偽（`play_stamp` が今日のマスだけ）・通常だけ/VIP だけ/両方/どちらも無い・8 日超（文字の画面）・再表示の旨の条件（どの段も今日の段でない日は出さない。T3・U-3）・`FROM_HOME` は `login_bonus_list` の行を出さない・サイクルが 1 周した後（`last_day` = 1 で前サイクルのスタンプを引き継がない）・カムバックだけが配られた日
- `FetchLoginBonusCalendarsUseCase` / `ReceiveVipLoginBonusUseCase`（偽の Repository）: 成功でメモリが更新される・VIP の段だけ `is_granted_now` が真で通常は変わらない・`ApplyUpdatedResourcesUseCase` が呼ばれる・失敗で何も反映しない・`BUSINESS` の `can_reuse` が偽（キー作り直し）
- `ApplyUpdatedResourcesUseCase`: `trx_item_list` の差し替え（`mst_item_id` で置換・無ければ追加・他の行は残す）・`trx_diamond` の置換・キー無し/null/型違いで何も壊さない・他のキーを無視・ホームの `CoinAmount`・`DiamondTotal` に反映される
- `LoginBonusCalendarApiRepository`: list は冪等キー無し・receive は冪等キーつきで本文に `mst_vip_login_bonus_id`・`ApiResult` の失敗が `AppError` になる（`login_api_repository_test` の方式）
- `login_bonus_presenter`（シーンを作る）: `FROM_LOGIN` は通信しない・段の有無でセクションの表示が切り替わる・受け取りボタンは `can_re_receive` のときだけ・押下中は無効・成功で VIP のマスがスタンプ・BUSINESS で取り直し・タップでホーム（ボタンのタップでは閉じない・連打で 1 回）・アニメーション中のタップは閉じず最終状態へ
- スタンプ: `apply_state(play=false)` が最終状態（押印・縁取り）・`play=true` の後に完了すると同じ最終状態・再受け取りでスタンプが外れて再度押される
- `HomePresenter`: ボタンで `goto_login_bonus_from_home` が 1 回呼ばれる（連打でも 1 回）。メール・お知らせは何も起きない（P3 のまま）
- `SceneRouter` の定数の実在（既存の方式）
- 依存方向: `make check-deps`（新ファイルが P1・P2・C1 に違反しないこと）

## 10. ドキュメント更新（実装 S5 で行う。ここでは一覧だけ）

| 文書 | 更新 |
| --- | --- |
| `.claude/api.md` | login の新キー・`POST /login_bonus/list`・`POST /login_bonus/receive`（項目はサーバーの api.md を指し複製しない）、冪等キーの対象に receive を追加、`updated_resources` の節を「ホームが読む 3 種を取り込む」へ |
| `.claude/architecture.md` | 階層の例に `core/presentation/item_icon/`・`safe_area_margins.gd` の移動、login の構成（`login` の保持はカレンダーも）、`ItemIconResolver` を core/domain に置く理由 |
| `.claude/implementation-history.md` | この機能の経緯 |
| `docs/ASSETS.md` | アイコン（5-4） |
| `CLAUDE.md` | 命令・コマンドの表に `make icons`・`make check-icons`（`make check` に含むなら） |
| `docs/design/title-to-home/client_design.md` | login の保持先に新キーを 1 行（Nexus の全体設計 8 節のドキュメント更新と同じ。仕様は Nexus を指す） |

## 11. 確認手順（S5 で動画に撮る操作と期待結果）

### 11-1. 前提

- 撮影の基本は Nexus の `docs/workflow/recording.md`（Movie Maker・540 幅へ変換・PR にドラッグ&ドロップ）。サーバーは動画用のシードを入れる（`make seed` → `make seed-recording`）。**カレンダー用のシナリオは S2（サーバー設計）が決める録画用のシーダーに足される**（overview 8 節 ①〜⑧）。以下の「シード」は仮の名前で、S2 のマージ後に実際のシナリオ名へ直す
- 1 コマずつ見る: `--e2e-dwell=<秒>` で止める。アニメーションは `ffmpeg -ss <秒> -frames:v 1` で、押印前（0.2 秒）・押印中（0.5）・着地後（1.1）の 3 枚を、**`E2E: 画面 <path>` の行の `t` に足した秒**で抜いて見る（動画の先頭からの秒ではない。次のドライバーの拡張）。**動画では 60fps を測れない**（7 節。測定は別の手順）
- ドライバー（`debug/e2e_driver.gd`）の拡張（V3）:
  - `--e2e-open-login-bonus`: 通常の流れ（ログインボーナス → ホーム）の後、ホームで `ACTION_DELAY`＋dwell 待って**「ログインボーナス」ボタンをクリック**し、`FROM_HOME` の画面を開く。その画面で dwell 待ち、中央（ボタンの無い位置）をクリックしてホームへ戻り、終了する
  - `--e2e-receive=home|login`（**押す入口を指定する。値なしは不可**）: 指定した入口の画面で、受け取りボタンが出ていれば dwell の後に**ボタンの中心をクリック**する。ボタンが無ければ押さず「ボタン無し」を出力する。**指定と違う入口の画面では押さず、dwell の後に中央（ボタンの無い位置）をクリックしてホームへ進む**。押した後は dwell 待ってから中央をクリック
  - `--e2e-stale-receive`（**値なしのフラグ**。入口は `--e2e-receive=home|login` が決める）: `--e2e-receive` が押す画面で、押す直前にドライバーが `ReceiveVipLoginBonusUseCase` を直接呼んで先にサーバー側を受け取り済みにしてから、古い画面のボタンを押す（BUSINESS → 取り直しの再現）
  - `--e2e-fail-bonus=<種別>`: `/login_bonus/*` の応答を偽の失敗にする（`--e2e-fail-login` と同じ種別: 503 / 409 / 429 / network。回数は `--e2e-fail-count`）
  - `--e2e-frame-probe=<秒>`: 7 節の計測を出力
  - **基準時刻の出力**: 既存の `E2E: 画面 <path>`（画面が変わった最初のフレームで出る行）に **`frame=<Engine.get_frames_drawn()> t=<秒>`** を足す。**`t` は 30fps 固定の録画の時間（`frame ÷ 30`。Movie Maker の固定 delta の積算 `_elapsed` と同じ値）**で、動画の先頭からの秒に等しい。押印の撮るコマは、ログインボーナス画面の行の `t` に **0.2・0.5・1.1 秒**（押印前・押印中・着地後。**通常は 0.7 秒・VIP は 0.9 秒で着地し、VIP の演出の終了は 1.0 秒ちょうどなので、着地後は 1.1 秒に撮る**）を足して `ffmpeg -ss` を決める。`--e2e-shot` の写真は画面ごとの相対時刻で撮るので影響なし。**再受け取りの押印は、応答を受けた時点で `E2E: 受け取り応答 frame=… t=…` を出し**、それに 0.2（外れた状態）・0.5・1.1 秒を足す（押印の開始は応答 +0.3 秒、着地 +0.7 秒、終了 +0.8 秒）
  - 写真: ログインボーナス画面は 1.2 秒後。`FROM_HOME` の画面は `bonus_home` の名前で撮る（読み込み完了後）。終了時に `E2E_RESULT:` の行で、画面の段の状態（今日の日数・マスの状態の並び・ボタンの有無）を出す（文字ではなく UseCase の結果を出して目視と照合する。ホームの前例と同じ）

### 11-2. ケース（動画 1 本 1 ケース。期待結果は要件の体験の番号と対応）

| # | シード（サーバーの前提状態） | 操作（引数） | 期待結果 |
| --- | --- | --- | --- |
| A | 新規ユーザー（1 日目）・VIP レベル 0 の VIP マスターあり | `--e2e-reset --e2e-dwell=2` | 通常・VIP の 2 段が 1〜7 日目で並ぶ。両方の「1 日目」が今日（縁取り＋「今日」）。**通常 0.3 秒後・VIP 0.5 秒後に 1 日目へスタンプ**。2〜7 日目は暗い（未来）。下に「今日配られた報酬」（絵＋名前＋数量）。7 日目のマスは幅が広い。体験 1 |
| B | 3 日目まで受け取り済み・昨日 login（今日 4 日目を配る） | 同上 | 1〜3 日目は押印済み（アニメーションなし）で少し暗い、4 日目だけアニメーション、5〜7 日目は未来。体験 2・3 |
| C | B のあと**同じ日にもう一度** login（`--e2e-reset` なし） | `--e2e-dwell=2` | 「本日のログインボーナスは受け取り済みです」が上に出る。4 日目は**最初から押印済み**でアニメーションなし。「今日配られた報酬」の行は無い。体験 4 |
| D | 6 日目まで受け取り済み・昨日 login（7 日目を配る） | 同上 | 7 日目（広いマス）にスタンプ。全マス押印後の最終状態。特別な演出なし。体験 5 |
| E | 7 日目まで受け取り済み・昨日 login（サイクルが 1 周して 1 日目） | 同上 | 前のサイクルのスタンプは引き継がれず、1 日目が今日・スタンプ。2〜7 日目は未来。体験 6 |
| F | VIP の該当レベルのマスターが無い（VIP の項目が null） | 同上 | 通常の段だけ。VIP の見出し・マスは出ない。体験 7。通常も無効なら「受け取り済み」の文字画面（文字の画面の確認） |
| F2 | 通常が無効（通常の項目が null）で VIP の項目だけある | 同上 | **VIP の段だけ**が出る（通常の見出し・マスは無い）。VIP の今日のマスにスタンプ。体験 7 |
| G | 通常・VIP のどちらか（または両方）が今日の途中で有効になった日（`day` が過去のまま・今回配っていない・今日の分でもない） | 同上 | その段は**全日を未強調**（スタンプも強調も無い）で出る。再表示の旨は、どの段も今日の段でないとき出ない。体験 8 |
| H | 通常の日（再受け取り不可）で、login を済ませた状態 | `--e2e-open-login-bonus --e2e-dwell=2` | ホームに「ログインボーナス」ボタン（メール・お知らせの隣。バッジなし）。タップで読み込み中 → カレンダー。**アニメーションなし**・今日のマスは押印済み・受け取りボタン無し。ボタン以外のタップでホームへ戻る。H1〜H5 |
| I | VIP を今日受け取り済み・課金で VIP レベルが上がった状態（`vip_point` を加算。録画シナリオ ⑧） | `--e2e-open-login-bonus --e2e-receive=home --e2e-dwell=2` | **押す画面は `FROM_HOME`**（login 直後の画面にもボタンが出ているが押さず、中央クリックでホームへ進む）。`FROM_HOME` の VIP の段の下に**受け取りボタン**。押すと「受け取り中…」→ **VIP の今日のマスのスタンプが外れて再度押される**・ボタンが消える・報酬の行に新レベルの報酬。通常の段は変わらない。ホームに戻ると**コイン・ダイヤ・スタミナの値が増えている**（`E2E_RESULT` の所持数と照合）。R1〜R7・Q31 |
| J | I と同じ状態を **login 直後**に（同じ日の 2 回目の login で `can_re_receive` が真） | `--e2e-receive=login --e2e-dwell=2`（`--e2e-open-login-bonus` なし） | **押す画面は `FROM_LOGIN`**。login 直後の画面にボタンが出て、押すと I と同じ（スタンプ・報酬の行・ホームの所持数）。H4 |
| K | I の状態で、押す前に別の経路で受け取り済みにする | `--e2e-open-login-bonus --e2e-receive=home --e2e-stale-receive --e2e-dwell=2`（`login` 入口で試すときは `--e2e-open-login-bonus` を外し `--e2e-receive=login`） | **押す画面は `FROM_HOME`**（先行受け取りは `--e2e-receive` と同じ画面で、押す直前）。ボタンを押す → サーバーが業務エラー → 状態を取り直してボタンが消え「状態を更新しました」。画面は壊れない。二重受け取りは起きない（ホームの所持数が 1 回分） |
| L | 通常の日 | `--e2e-open-login-bonus --e2e-fail-bonus=network --e2e-dwell=2` | `FROM_HOME` の読み込みが失敗し、エラー文＋「再試行」。タップでホームへ戻れる |
| M | **この機能を入れる前のサーバーの版**（新キー・新 API が無い。用意: サーバーのリポジトリで、この機能の最初の変更の親のコミットを別の作業ツリーに取り出して起動し、`NEXUS_API_BASE_URL` をそちらに向ける。コミットの特定と起動手順は S2 の README に依存するので S-10 に含める） | `--e2e-dwell=2` | カレンダーを出さず、今の文字の画面（「ログインボーナス!」＋行、または「受け取り済み」）。落ちない。旧サーバーのときホームのボタンを押すと、list が 404/エラーになり、L と同じ表示（要確認の挙動。12 節 Q-7） |
| N | アイコンの確認 | `godot --path . debug/icon_gallery.tscn --e2e-shot=<dir>`（形は実装で決める） | 全アイコンが 1 枚に並ぶ。マスターに在って絵が無い ID は赤。`unknown`・`category_*` も見える |

- 未知の `content_type`・`unit`・`equipment` の絵（`unknown`）は、サーバーが不正な行を除く（U-1 の既定案）ので e2e では再現しにくい。単体テストと、ギャラリー（N）の `unknown` で確かめる。報酬が `unit`・`equipment` のマスターを録画用シードで足せるなら、ケース A に足す（S2 に依頼）
- 各ケースで、**押印の 3 コマ**（`E2E: 画面` の `t`＋0.2・0.5・1.1 秒。再受け取りは `E2E: 受け取り応答` の `t` から）、ホームの値、`E2E_RESULT` の行（マスの状態の並び・ボタンの有無）を PR に載せる

### 11-3. その他の確認（動画以外）

- `make check-quiet`（依存方向 → lint → format → テスト → 複製の起動。`make check-icons` を含める場合はそこも）
- 製品用の複製: `make check-release-quiet`（`preload` したアイコンの実在・`tools/icons`・`debug/` の分類）。**実機の書き出しは未確認のまま**（CLAUDE.md の「未確認」）
- 実測: R2（7 節）・R4（5-6）の結果を PR に書く。**実機（iPhone X）での 60fps は未確認**と明記する

## 12. 未解決点

### S2 マージ後の差分の洗い出し（サーバー設計が確定してから直す）

この文書は overview の名前で仮置きした。S2 のマージ後、次を突き合わせて直す（担当: クライアント設計の書き手 + 別のレビュー）。

| # | 見る点 | この文書の仮置き |
| --- | --- | --- |
| S-1 | 新キーの名前・各項目の名前・型・null 可否 | 通常用 `login_bonus_calendar`・VIP 用 `vip_login_bonus_calendar`。段は 4 節の形。真偽値は真偽値型 |
| S-2 | `days` の形・`unique_id` を報酬に入れるか・日の中の並び | `[ {day, rewards:[{type,id,amount,metadata}]} ]`。`unique_id` は読まない |
| S-3 | receive の応答（`updated_resources` と `trx_vip_login_bonus`）・リクエストのパラメータ名 | `mst_vip_login_bonus_id`。`trx_vip_login_bonus.day`・`.vip_level` |
| S-4 | 条件を満たさないときのエラー（HTTP 299 の `error_code`。クライアントは `BUSINESS` として扱い、コードで分岐しない） | コードを見ない。全 BUSINESS で取り直し |
| S-5 | `updated_resources` に VIP の状態・`trx_stamina_list` の主キーが含まれるか | `trx_item_list`（`mst_item_id`）・`trx_diamond`・`trx_stamina_list`（`mst_stamina_type`。仮） |
| S-6 | list の冪等キーの扱い（任意）・ロック・失敗時の挙動 | 付けない |
| S-7 | 不正な行（U-1）のときに日のマスが空になるか | 空の日は `unknown` の絵のみ |
| S-8 | wallet 系報酬の `type`・`id`（`gold` のとき `id` も `gold` か） | `id` で引く（`type` と `id` が同じ値の前提） |
| S-9 | 録画用シードのシナリオ名・VIP の再受け取りの作り方 | 11-2 の A〜K を実名に直す |
| S-10 | 旧サーバーが list・receive に返す応答（404 など。11-2 の M）と、**旧サーバーの版の取り出し方・起動手順（S2 の README か Nexus の recording.md に書く。無ければ S2 に依頼）** | L と同じエラー表示 |

### 確認事項（人が決める。既定案つき）

| # | 確認事項 | 既定案 |
| --- | --- | --- |
| Q-1 | 星の行（72）をこの画面から外してよいか（縦の高さを収めるため。1-4） | **外す**（余白 48＋①② で見積り 1512 が使える高さ 約 1599 に収まる。星の行 72 を残すと 1584 で余裕が約 15 になるので、残すなら実測で確かめる） |
| Q-2 | 新しい UseCase・保持を、既存の `contexts/login` に置くか、サーバーの `Domain/LoginBonus` に合わせて `contexts/login_bonus` を新設するか（overview は「サーバーは分離した LoginBonus ドメイン」と決めたが、クライアントのコンテキスト名は言っていない） | **既存の `login` に置く**（画面・保持・`LoginUseCase` が既にあり、分けると `login` ↔ `login_bonus` で保持の受け渡しが増える）。名前を揃えたいなら、`login_bonus` を新設して画面ごと移す（移動の PR を別に出す） |
| Q-3 | 再受け取りの後の「今日配られた報酬」の行: `FROM_LOGIN` は既存の行の後ろに足す、`FROM_HOME` は再受け取りの報酬だけ出す（3-2。R6 は「再受け取りの応答で返し、行に出す」までしか決めていない） | 3-2 のとおり。見出しは同じ「今日配られた報酬」 |
| Q-4 | `make check` に `check-icons`（生成物が最新か・規格）を足すか | **足す**（軽い。足し忘れの SVG・生成物の食い違いを CI で止める） |
| Q-5 | 再受け取りの押印を「一度外して押し直す」か、「押印済みのまま弾むだけ」か | **外して押し直す**（6 節。変化が分かるため） |
| Q-6 | 60fps を保てるかの実機（iPhone X）での確認の手段（書き出しテンプレートが無い）。人が実機で測るか、相当の端末か | **この設計では実機を測らない**。7 節の指標（ドロー呼び出し・オブジェクト数の比）で判断し、実機は別の確認として残す。実機で測れる人がいれば同じ 2 秒の手順を使う |
| Q-7 | 新クライアント × 旧サーバーで、ホームの「ログインボーナス」ボタンを押したときの扱い（list が無い）。エラー表示で足りるか、ボタンを出さないか（login の新キーが無いことで旧サーバーと分かる） | **エラー表示（L と同じ）で足りる**（旧クライアントは未配布で、旧サーバーとの組み合わせは移行の短い間だけ） |
| Q-8 | 8 日を超える `loop_days`・1 未満のとき、画面全体を文字にするか、その段だけ落とすか（C1 は「カレンダーを出さず今の文字の画面に落とす」） | **画面全体を文字にする**（段ごとに混ぜると見た目が揃わない。8 日超は今の運用に無い） |

### 仮置き（既定案で進める）

- 画面の入口の渡し方: 入口ごとの継承シーン（1-1）。`SceneRouter` に引数の口を足す案は採らない（オートロードに状態を置かないため）
- スタンプ: 赤橙の円の印＋白いチェック。`TRANS_BACK`・`EASE_OUT` の既定の overshoot。明るさ 1.3 倍・0.1 秒（6 節）
- マスの状態の明るさ・彩度（受け取り済み 0.8・未来 0.5/0.7）、縁取りの色・太さ（4px。色は黄〜橙）は実装時に画面で調整する（要件は「目安」）
- `ApplyUpdatedResourcesUseCase` の取り込み範囲はホームが読む 3 種のみ（3-3）
- `SafeAreaMargins` を `core/presentation` へ移す（1-4。他に置き場の案: login の presentation にコピー → 二重定義になるので採らない）
- 受け取りボタンのラベル「受け取る」・Toast の文言「状態を更新しました」・「読み込み中…」・「VIP ボーナス　VIP n」は固定文字（ja）
- `HomeText.format_number` を `NumberText` に寄せる整理は、V2 で一緒にするか後回しにするかを S5 で決める（挙動は変えない）

### 実行で確かめる点（S5）

- 縦の高さの実測（最大構成で収まるか。1-4 の見積りの修正）
- `.svg` の import 後の容量・見た目（5-6・R4）、`--export-pack` が使えるか
- ギャラリーで `master.db` を debug 専用に読む方法（5-6）
- 継承シーンと `@export` の `entry`、`TapCatcher` の `gui_input` が背景動画・Panel の下でタッチ・マウスの両方を受けるか（`mouse_filter` の組み合わせ）
- `Tween` を画面離脱時に kill する漏れが無いか（連続で開閉して確認）
