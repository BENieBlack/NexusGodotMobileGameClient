# 無償ダイヤの trx_item 管理への移行 クライアント設計

- 要件: `Nexus/docs/requirements/free-diamond-item.md`（F9 (5)・F10・F11・F3・Q10・Q14・Q15。確認事項 Q1〜Q24 は確定済み。**仕様の正本は要件**。ここには複製せず節番号で指す）
- 全体設計: `Nexus/docs/design/free-diamond-item/overview.md`（クライアントの変更 K1〜K4（6 節）、未解決 U-1〜U-5）
- サーバー設計（正。マージ済み）: `NexusMobileGameServer-Laravel/docs/design/free-diamond-item/{db,api,sequence}.md`（login の `trx_diamond` は api.md 3.1、`login_bonus_list` は 3.3、`updated_resources` の約束は 2 節、購入応答は 5.3、動画用シードは 8 節・db.md 6.1）
- 要件・サーバー設計の追記（design-change。人の決定 Q-C7・Q-C8）: 表示名の配信（`mst_item__l10n`）と、クライアントの `ja` 固定の言語指定（5-3 のサーバーへの申し送り）
- 前提: [home-player-info のクライアント設計](../home-player-info/client_design.md)（ダイヤの合計は 4-2。`DiamondTotal`・login 応答の取り込みは 2-2・6 節。**ここには複製せず、差分だけ書く**）、[title-to-home](../title-to-home/client_design.md)
- 決定: `Nexus/docs/adr/0002-client-clean-architecture-ddd-lite.md`（3 層・master_data 共有モジュール）

旧クライアントは未配布で、互換は持たない（D7・Q6）。サーバーが先、クライアントは同じ時期に追従する（Q10）。**新しい画面・新しい API 呼び出しは足さない**。変更は、ダイヤの合計・ログインボーナスの表示・マスターの `MstItem` の読み取り（名前の表示。人の決定 Q-C2）。

## 0. 現状の確認結果（設計の前提。クライアントのコードを読んで確かめた）

| # | 確認したこと | 場所 |
| --- | --- | --- |
| a | `DiamondTotal.calculate(trx_diamond, trx_item_list)` は、有償 `paid_amount` に加えて**暫定の項 `trx_diamond.free_amount`** と `trx_item_list` の `free_diamond` の `free_amount`（削除行を除く）を足している。ファイル冒頭のコメントに「二重カウントしない理由」（暫定の 2 経路）が書いてある | `contexts/player/domain/services/diamond_total.gd` |
| b | `DiamondTotal` を呼ぶのは `GetHomeSummaryUseCase` だけ（`state.trx_diamond` と `state.trx_list("trx_item_list")` を渡す）。`HomeSummary.diamond_total` に入り、presenter は桁区切りにして出すだけ | `get_home_summary_use_case.gd`、`home_presenter.gd` |
| c | login 応答の `trx_diamond` は `JsonReader.get_dict` で取り、null・キー無し・型違いは `{}`。`LoginDataResult` → `ApplyLoginDataUseCase` → `PlayerState.trx_diamond`（辞書のまま）。**辞書の中身（`free_amount` の有無）は見ていない**ので、サーバーがキーを外してもこの経路は壊れない | `login_response.gd`、`login_data_result.gd`、`player_state.gd` |
| d | `trx_item_list` は `PlayerState.trx_lists` に行の辞書のまま入る（キー無し・null は `[]`）。形の変更は無い（api.md 3.2） | `player_state.gd` |
| e | **`updated_resources` を読む処理は無い**。`.gd` を `updated_resources` で検索しても 0 件。クライアントが呼ぶ API は `auth/*`（version・sign_up・sign_in・login・refresh_token）と `agreement/*` だけで、ガチャ・交換・購入・メールの呼び出しは無い。**login 応答の `trx_diamond`・`trx_item_list` は `updated_resources` ではなく現在値の全量**（api.md 2 節の login の行） | `contexts/*`、`core/`（grep） |
| f | `total_free_diamond_amount`・`paid_diamond_amount`・`trx_diamond_list`・`free_amount` の `trx_diamond` 経由の読みは、`DiamondTotal` 以外に無い（`CoinAmount` の `free_amount` は `trx_wallet_list` の `coin` で別物）。旧キー `trx_diamond_list` は読まない（テストで固定済み） | grep |
| g | ログインボーナスの表示 `LoginBonusPresenter._resource_type_label(type)` は `type` だけで表示名を決める（`"diamond"` → 「ダイヤ」、`"item"` → 「アイテム」）。1 行は `種別 (ID:<id>) x<amount>`（グレードがあれば添える）。**`id` を見て表示名を変える処理は無い**。サーバー変更後、無償ダイヤの要素は `type = item`・`id = free_diamond` になる（api.md 3.3）ので、そのままだと「アイテム (ID:free_diamond) x50」と出る | `login_bonus_presenter.gd`、`login_bonus.gd` |
| h | **クライアントは今 `mst_item` を読まない**（`master_data` の読み取りモデルは `mst_gacha`・`mst_unit`・`mst_equipment`、スタミナ用の `mst_player_level`・`mst_config` だけ）。ログインボーナスの表示名はコード中の固定文字（種別の `match`）で、ID の表示名の解決は無い。**Q-C2 の決定（名前を `mst_item` から引く）でこの前提を変える**（5 節） | `master_data/` |
| j | **サーバーは `mst_item` と `mst_item__l10n` を配信する**。`MasterDataExporter` は mst DB の `SHOW TABLES LIKE 'mst_%'` の**全テーブル**を出力し、`__l10n` は親テーブルと同じ SQLite ファイル（`mst_item_{hash}.sqlite`）に入れる。version API の `master.tables` のキーは親名（`mst_item`）。`mst_item__l10n` の列は `deploy_key`・`mst_item_id`・`language`・`name`・`description`（null 可）、主キーは `(mst_item_id, language)`。対応言語は `api/config/language.php` の `supported`（`ja` ほか 14 言語。既定 `ja`）。配信の仕組みを足す必要は無い | サーバー `tool/app/Services/MasterDataExporter.php:40-45,94`、`packages/nexus-core/.../create_resource_tables.php:58-91`、`.claude/database.md` 6・7 節 |
| k | **サーバーに `mst_item__l10n` の行を入れるシーダーが無い**（`MstItemSeeder` は `mst_item` だけ。`mst_item__l10n` を書く処理はコード全体で見当たらない。`free_diamond` の行も `type = currency`・`effect = none` の `mst_item` だけ）。サーバーの free-diamond-item の設計（db.md・api.md）にも名前の配信は無い。**このままでは配信は有っても `name` の行が無く、クライアントは常にフォールバックを出す** | サーバー `api/database/seeders/MstItemSeeder.php:144`、grep |
| l | **クライアントは言語を持たず、サーバーへも送っていない**（`language`・`locale`・`Accept-Language` を `.gd` で検索して 0 件。`ApiClient._build_headers` が付けるのは `Content-Type`・`Accept`・`Authorization`・`X-Master-Hash`・`X-Platform`・冪等キーだけ）。`MstUnit` の冒頭コメントに「多言語名（l10n）は未対応」とある。ガチャ・ユニットも l10n を読んでいない。`MasterDatabase.select_rows(table, sql, bindings)` は親名（`mst_item`）のキーで引き、同じ SQLite の `mst_item__l10n` にも SQL で届く（同梱 `data/master.db` には `mst_item` が無く、`select_rows` は空配列を返す） | `api_client.gd:_build_headers`、`master_data/data/local/master_database.gd`、`mst_unit.gd` |
| n | **サーバーは言語指定を受ける仕組みが既にある（新しい受け口は要らない）**。ミドルウェア `ResolveLanguage` が `bootstrap/app.php` の **api グループの先頭（全 API）** で、リクエストヘッダー **`Accept-Language`** を解釈する（`ja-JP,ja;q=0.9,en;q=0.8` のような重み付きも可）。`config('language.supported')`（`ja`・`en`・`zh-TW`・`zh-CN`・`hi`・`es`・`fr`・`ar`・`id`・`pt`・`bn`・`ru`・`de`・`ko`）に無い値・**ヘッダーが無いとき**は既定 `ja`。結果は `ApiSession::getLanguage()`（と `app()->setLocale`）で取れる。独自ヘッダー・クエリ・ボディの `language` は無い。`X-Platform`（`maintenance` グループにだけ付く）と違い、**除外ルートが無い** | サーバー `api/app/Http/Middleware/ResolveLanguage.php`、`api/bootstrap/app.php:36-38`、`.claude/api.md:18` |
| o | **現状、`ApiSession::getLanguage()` を応答の組み立てに使う API はメール一覧（`MailboxItemAssemblyService`。`mst_message__l10n`）だけ**（`app` 配下の検索）。ログインボーナス・login・ガチャ・購入の応答は l10n を使わない（名前は配信のマスターで渡す）。つまりクライアントが `Accept-Language` を送っても、この機能の API の応答は変わらない。**意味があるのはマスターの名前の引き（5 節）と、将来のメール一覧など** | サーバー `api/app/Domain/Mailbox/Services/MailboxItemAssemblyService.php:33-39` |
| m | `master_data_loaded`（マスター切り替え完了）は、タイトルの最初（認証の前）の `CheckMasterDataUseCase` で起きる。ログインボーナス画面は login の後なので、更新が成功していれば切り替え済みの DB を読む。失敗・未配信なら同梱 DB（`mst_item` なし）になる | `api.md`、`docs/MASTER_DATA.md` |
| i | `api.md` の「Resource タイプ一覧」の `diamond` の行（「ダイヤ（課金通貨）」）は、サーバーが `ResourceType::DIAMOND` を廃止（F9 (1)）するので実態と合わなくなる | `.claude/api.md` |

## 1. 変更の一覧（全体設計 K1〜K4 の具体化）

| # | 変更 | 場所 | 根拠 |
| --- | --- | --- | --- |
| C1 | **ダイヤ合計から暫定項を削除**。有償 = `trx_diamond.paid_amount`、無償 = `trx_item_list` の `free_diamond` の `free_amount`（`is_delete` を除く）だけにする（2 節） | `player/domain/services/diamond_total.gd`、`diamond_total_test.gd`、`login_response_test.gd`（フィクスチャの `free_amount`） | K1・F10・Q10 |
| C2 | **ログインボーナスの `item` の表示**。`diamond` の分岐を直し、`item` の名前を `mst_item`（l10n）から引いて出す。引けないときは `free_diamond` なら「無償ダイヤ」、他の `item` は従来の「アイテム (ID:…)」（3 節） | `login/domain/entities/login_bonus.gd`（冒頭コメント含む）、`login_bonus_presenter.gd`、`login_bonus_presenter_test.gd`、新しい UseCase（3-3） | K2・F9 (5)・api.md 3.3 |
| C3 | `updated_resources`・`total_free_diamond_amount` は**読む仕組みを作らない**（4 節。書くのは将来の機能のための注意だけ） | なし（`.claude/api.md` に注意書き） | K3・K4・F11 |
| C4 | **マスターに `MstItem` を足す**（5 節）。`master_data` に読み取りモデル・Repository の契約・SQLite の実装。サーバーの追加（`mst_item__l10n` の行）が前提（別タスク・5-3） | `master_data/domain/`、`master_data/data/`、`app/app_context.gd`、`docs/MASTER_DATA.md` | Q-C2 |
| C6 | **言語 `ja` を固定で持ち、全 API リクエストに `Accept-Language: ja` を付ける**（5-2）。`ApiConfig.language()`（定数 `ja`）、`ApiClient._build_headers()` に 1 行、`MstItem` の l10n の引きも同じ値 | `core/data/config/api_config.gd`、`core/data/http/api_client.gd`、`api_client_test.gd`、`api_config_test.gd` | Q-C8 |
| C5 | ドキュメント: `.claude/api.md` の Resource タイプ一覧、home-player-info の 4-2 の暫定記述（7 節） | `.claude/`、`docs/design/home-player-info/client_design.md` | Q14 |

層の分担（home-player-info 2-1 のとおり。合計は domain の純粋関数、presenter は文字列にするだけ）:

| 層 | 責務（この機能の差分） |
| --- | --- |
| presentation（`login/presentation/login_bonus/`） | `LoginBonusPresenter` が新しい UseCase の結果を文字列にする。名前が空のときのフォールバックの文字は presenter でなく domain の値（3-2） |
| domain（`login/domain/`） | `LoginBonus.is_free_diamond()`、新しい UseCase `GetLoginBonusDisplaysUseCase`（ログインボーナスと `MstItemRepository` から表示用の値を作る。3-3） |
| domain（`master_data/domain/`） | `MstItem`（読み取りモデル）・`MstItemRepository`（契約）。読み取りのみ |
| data（`master_data/data/`） | `LocalMstItemRepository`（SQLite。`mst_item` と `mst_item__l10n`） |
| 変わらない | ダイヤの合計（`player/domain/services/diamond_total.gd`）は `mst_item` を使わない。ホームの通貨ラベル「ダイヤ」は有償＋無償の合計の見出しで固定文字（無償ダイヤの名前ではない）のまま |

`tools/prepare_release_project.py` の分類の変更は要らない見込み（新規ファイルは `master_data/`・`contexts/` の下）。S5 で `make check-release` で確かめる。

## 2. ダイヤの合計（C1。home-player-info 4-2 の差分）

規則は次の 2 行だけになる（4-2 の「足す規則」の暫定項を除いたもの）。

```
有償 = trx_diamond.paid_amount                                   （trx_diamond が null・{}・キー無し・削除行 → 0）
無償 = Σ trx_item_list[mst_item_id == "free_diamond"].free_amount （is_delete が真の行は除く。行が無い → 0）
合計 = 有償 + 無償
```

| 項目 | 扱い |
| --- | --- |
| `trx_diamond.free_amount` | **読まない**。サーバーは応答から外す（F6・F8）。万一キーが来ても（旧サーバー・誤配信）足さない。二重に数える危険を作らないため、「あれば足す」ではなく**無視する**（home-player-info 4-2 の「キーが在るかで足す」は、移行期間の安全策だったので役目を終える） |
| `trx_diamond` が `null`（login 応答。api.md 3.1。サインアップで作られるので通常は有る） | `{}` として受けて有償 0。無償だけ（`trx_item` の分）を表示する。**エラーにしない・「-」にしない**（ホームの「欠けているとき」の表と同じ。home-player-info 1-3） |
| `free_diamond` の行が無い | 無償 0 |
| `free_diamond` の行が `free_amount = 0` で残っている（0 になっても行は残る。api.md 3.2・db.md Q8） | 無償 0。**行があることを「持っている」扱いにしない**（表示は数値の 0） |
| `trx_item` の `free_diamond` 行の `paid_amount` | 足さない（今と同じ。有償は `trx_diamond` だけ） |
| platform | 見ない（応答がすでに `X-Platform` の行だけ。他 platform の有償は見えない仕様。D6・F12） |
| `is_delete` | 真偽値・0/1 のどちらでも読む（`PlayerState.is_row_deleted`。今のまま） |

`PlayerResourceIds.FREE_DIAMOND`（`"free_diamond"`。サーバーの `mst_item.id` と一致させる二重管理。home-player-info 2-2）はそのまま使う。`DiamondTotal` の引数・戻り値・呼び出し側（`GetHomeSummaryUseCase`）は変えない。ファイル冒頭のコメントは、暫定項と「二重カウントしない理由」の説明を消し、上の規則と「無償は `trx_item` の 1 行に集約された（free-diamond-item）」だけにする。

home-player-info 4-2 にあった申し送り（既存の無償は「移して列を削除」でコピーしない。D4）は、サーバー設計 db.md が「最初から存在しなかったことにする」（F6）で満たしている。

## 3. 報酬の content_type の変化（C2）

### 3-1. 何が変わるか

login の `login_bonus_list` の無償ダイヤの要素が `type: diamond` → **`type: item`**、`id` は `free_diamond` に統一（6 日目の混在も解消。api.md 3.3）。数量・metadata は同じ。`LoginResponse` → `LoginBonus` の変換は `type`・`id` を文字列のまま持つだけなので**変更不要**。

クライアントが `type` で分岐しているのは `LoginBonusPresenter._resource_type_label` だけ（0 節 g）。

### 3-2. 表示の決め方

- 判定「無償ダイヤか」は `LoginBonus.is_free_diamond()`（`type == "item"` かつ `id == "free_diamond"`。`id` だけで判定しない）。`login` コンテキストの中で閉じる（`player` の定数に依存しない。architecture.md の依存ルール）。`"free_diamond"` の定数は `LoginBonus` の側に持つ（二重管理。コメントにサーバーの `mst_item.id` の場所を書く）。
- **表示名は `mst_item` の名前を優先する（人の決定 Q-C2）**。`type == "item"` の行は、`MstItemRepository` から `id` の名前（l10n。5 節）を引く。
- 1 行の形（グレードの扱いは今のまま）:

| 行 | 名前が引けた | 名前が引けない（`mst_item` が無い・行が無い・`name` が空・DB が同梱） |
| --- | --- | --- |
| `item` / `free_diamond` | 「`<name>` x100」 | **「無償ダイヤ x100」**（人の決定 Q-C1 の文言。固定文字） |
| `item` / 他の ID | 「`<name>` x…」（ID は出さない） | 従来どおり「アイテム (ID:…) x…」 |
| `unit`・`equipment`・`gold`・`stamina` | 従来どおり（`mst_item` を引かない） | 同左 |
| `diamond`（旧）・`paid_diamond`・未知の種別 | 種別をそのまま出す（`_` の分岐。互換の特別扱いはしない。D7）。`diamond` の分岐は**削除** | 同左 |

- 「他の `item` も名前を引く」は人の確認事項（Q-C6）。既定案は引く（ID のままより親切で、同じ仕組みで足りる）。
- `"diamond"` の分岐は削除する（サーバーが `ResourceType::DIAMOND` を廃止。F9 (1)）。有償ダイヤはログインボーナスに出ない（要件の前提表）ので `paid_diamond` の分岐は足さない。
- ホームの通貨ラベル「ダイヤ」は変えない（合計の見出し。`mst_item` を引かない。home-player-info 1-2）。

### 3-3. 表示用の値の作り方（層の分担）

- `GetLoginBonusesUseCase.handle() -> Array[LoginBonus]` は変えない（他の呼び出し元・テストを壊さない）。新しい **`GetLoginBonusDisplaysUseCase.handle() -> Array[LoginBonusDisplay]`**（`login/domain/`）を足す。`LoginBonusDisplay` は「`bonus`（`LoginBonus`）と `item_name`（`type == item` で名前が引けたときだけ。それ以外は空文字）」の読み取り用の値。
- UseCase は `GetLoginBonusesUseCase` と `MstItemRepository`（`master_data/domain` の契約）を受け取り、行ごとに名前を引く（言語は Repository が持つ。5-2）（行数は数件。キャッシュは持たない）。名前が引けない・空は `item_name = ""`。例外にしない。
- presenter は `LoginBonusDisplay` から上表のとおり文字列を作る（フォールバックの「無償ダイヤ」は `LoginBonus` の側の定数。presenter に直書きしない）。`setup()` は新しい UseCase を受ける形にする（テストは偽物の Repository を渡す）。
- 読むのは画面を開くとき 1 回（0 節 m のとおり、通常は切り替え済みの DB）。画面表示中の `master_data_loaded` は購読しない。

### 3-4. 確認事項

| # | 確認事項 | 既定案 |
| --- | --- | --- |
| Q-C6 | `free_diamond` 以外の `item` も名前を `mst_item` から引くか（ID のままにしない） | 引く（人の指示の既定案。同じ仕組みで足りる）。引けなければ従来の「アイテム (ID:…)」 |

## 4. `updated_resources` と購入・消費の応答（C3）

**今のクライアントはどちらも読まない**（0 節 e）。この機能でサーバーの応答の形が変わっても（`trx_diamond_list` → 単数の `trx_diamond`、購入応答から `paid_diamond_amount`・`total_*` を外す。api.md 2・5.3 節）、**クライアントは壊れず、変更も要らない**。

将来これらを呼ぶ機能（ガチャ・交換・購入・メール）を作るときの前提を、実装履歴ではなく `.claude/api.md` に短く書いておく（7 節）。ここで設計はしない（要件の対象外。K4・再取得方針は別機能）。

- `updated_resources` は「キーがあれば上書き、無ければ現状維持」（Q15）。**変更があった方だけ載る**ので、無償だけ使ったら `trx_item_list` だけ、有償だけなら `trx_diamond` だけ。
- `trx_diamond` は**単数のオブジェクト**（login と同じ形。`X-Platform` の行）、`trx_item_list` は**配列**（型が違う）。`trx_diamond_list` は無い。
- `trx_item_list` は**変更のあった行だけ**載りうる（login の全量とは違う）。マージは `mst_item_id` を主キーに行を差し替える形になる（全置き換えにしない）。この方式の決定は、読む機能を作るときの設計で行う。
- 購入応答には `paid_diamond_amount`・`total_free_diamond_amount`・`total_paid_diamond_amount` が**無い**（api.md 5.3）。残高は `updated_resources` から読む。要件 F3 の「`total_free_diamond_amount` は残高」は、API 設計の人の決定で応答から外れたので、**クライアントが読む対象は無い**（全体設計 K3 の想定を、サーバー設計が上書きした。7 節の仕様書の食い違いとして報告する）。
- 購入は body の `platform` と `X-Platform` に**同じ値**を送る（不一致は `INVALID_PLATFORM` 99003。api.md 5.2）。クライアントは `ApiConfig.platform()` の値を両方に使う（購入の機能を作るときに守る）。

## 5. マスター（C4。Q-C2 の決定で `MstItem` を足す）

人の決定（Q-C2）: `free_diamond` の表示名を `mst_item` から引く。0 節の j〜m のとおり、**配信の仕組みは足りている**（`mst_item`・`mst_item__l10n` は配信対象。`mst_config` と同じく `MasterDatabase.open_downloaded` が `table_files` の全ファイルを開く）が、**名前の行がサーバーに無い**（k）。

### 5-1. クライアントの追加（`mst_player_level`・`mst_config` の追加の仕方に倣う）

| 区分 | 場所 | 内容 |
| --- | --- | --- |
| 追加 | `master_data/domain/entities/mst_item.gd`（`MstItem`） | 読み取りモデル: `deploy_key`・`id`・`type`・`name`（l10n で引いた名前。無ければ空文字）。**ルール・判断は持たない**（フォールバックの文字は使う側） |
| 追加 | `master_data/domain/repositories/mst_item_repository.gd`（契約） | `get_by_id(id: String) -> MstItem`（無ければ null）。**言語は引数にしない**（Repository が構築時に持つ。5-2）。DB が開けない・テーブルが無い・l10n の行が無いときも例外にしない（行が無ければ null、`mst_item` の行だけ有って l10n が無ければ `name` 空の `MstItem`） |
| 追加 | `master_data/data/repositories/local_mst_item_repository.gd` | `LocalMstItemRepository.new(database, language)`。`MasterDatabase.select_rows("mst_item", sql, bindings)` で読む（親名のキー。`mst_item__l10n` は同じ SQLite ファイル）。`mst_item` の行を引き、`mst_item__l10n` から `language` の行を引く（`SELECT name FROM mst_item__l10n WHERE mst_item_id = ? AND language = ? LIMIT 1`）。NULL は既定値（`mst_config` の実装と同じ）。キャッシュは持たない |
| **変更しない** | `MasterDatabase.REQUIRED_TABLES`・同梱 `data/master.db` | `mst_item` は**必須にしない・同梱しない**（`mst_config` と同じ。配信が無い環境ではフォールバック表示になる） |
| 変更 | `app/app_context.gd` | `mst_item_repository()`（`ApiConfig.language()` を渡して作る）と `GetLoginBonusDisplaysUseCase` の生成・取得 |
| 変更 | `CLAUDE.md`（接続先の段落） | 言語は `ApiConfig.language()` の固定 `ja`（上書きなし）と一言 |
| `docs/MASTER_DATA.md` | `mst_item` を配信から読む（同梱しない。`REQUIRED_TABLES` に入れない）。l10n の読み方（5-2） |

### 5-2. 言語（人の決定 Q-C8: `ja` 固定。HTTP ヘッダーで全リクエストに渡す。`X-Platform` と同じ場所・同じ方法）

人の補足: 言語は `X-Platform` と同様に HTTP ヘッダーで渡す。ヘッダー名は「サーバーに既存の言語ヘッダーがあればそれに合わせる」ので、**既存の `Accept-Language`（0 節 n。標準のヘッダーで、サーバーの受け口・保持・不正値の扱いが既にある）を既定案にする**。独自の `X-Language` を新設する案は Q-C9（5-4）。以下は `Accept-Language` を前提に書き、`X-Language` に変える場合はヘッダー名の文字列だけが変わる（サーバーの追加が要る。5-3 S-4）。

| 項目 | 内容 |
| --- | --- |
| 保持する場所 | `ApiConfig.language() -> String`（`core/data/config/api_config.gd`。定数 `LANGUAGE_JA := "ja"` を返す）。**環境変数・`project.godot` による上書きは足さない**（固定。`platform` と違い切り替えない）。切り替えの機能（OS のロケール・設定画面）は別機能で、このとき `language()` の中身だけを差し替える |
| API への付け方 | `ApiClient._build_headers()` の 1 か所で、`request()` を通る**全リクエスト**に `Accept-Language: ja` を付ける（`X-Platform` と同じ位置・同じ流儀。version・refresh・sign_up を含む。ヘッダー名は定数 1 つ `LANGUAGE_HEADER` にして Q-C9 の結果で差し替えられるようにする）。`download()`（配信ホスト・規約本文）と Toast の `/broadcasting/auth` には付けない。署名には含めない。`set_platform("")` のような「付けない状態」は作らない（固定のため） |
| 付ける効果 | この機能の API の応答は変わらない（0 節 o。メール一覧が `mst_message__l10n` に使うだけ）。付けないときもサーバーは `ja` に倒すので、**付ける目的は「言語を明示する」ことと、将来の言語切り替えの足場**。サーバーが未対応の言語を受けたときも `ja` に倒れる |
| マスターの名前の引き | `LocalMstItemRepository` が `ApiConfig.language()` と同じ値（`ja`）で `mst_item__l10n` を引く。**API の言語とマスターの言語キーは同じ 1 か所の値**。`ja` の行が無ければ言語の連鎖は作らず、フォールバック（「無償ダイヤ」。3-2） |
| 層 | `ApiConfig` は `core/data`。domain は言語を知らない（UseCase は `MstItemRepository` を呼ぶだけ）。`AppContext` が `ApiConfig.language()` を Repository に渡す |

### 5-3. サーバーへの申し送り（別タスク。クライアント設計の範囲外。Q-C7 の確定により design-change を出す）

人の決定（Q-C7）: **サーバー設計・要件に「`mst_item__l10n` の行を足す」作業を追記する**。クライアントの表示名の引きが成立するために、サーバー側の設計に含めるべき内容:

| # | 内容 | 既定案・補足 |
| --- | --- | --- |
| S-1 | `mst_item__l10n` の行を入れる（`MstItemSeeder` と、本番のマスター投入の取り決め）。列: `deploy_key`・`mst_item_id`・`language`・`name`（`description` は null 可。`.claude/database.md` 6・7 節）。**`free_diamond` の `language = ja`・`name = 無償ダイヤ`** は必須 | **他の `item` も含める**（Q-C6 の確定で、ログインボーナスなどの `item` 全般の名前を引くため）。既定案は、`MstItemSeeder` にある `mst_item` の全行に `ja` の名前を入れる（行数の多さ・名前の中身は人が決める。最低でも報酬・ログインボーナス・課金パックの中身に出る `item` の分）。名前が無い `item` はクライアントが「アイテム (ID:…)」を出す |
| S-2 | 録画用シード（`RecordingLoginBonusSeeder` ほか）でも同じ行が入る | 動画（ケース 1・10）の前提 |
| S-3 | 配信（`/master-import/export`）。`MasterDataExporter` は `mst_%` の全テーブルを出力し、`mst_item__l10n` は `mst_item` の SQLite に入るので**エクスポートの変更は要らない**。作り直して、version API の `master.tables` に `mst_item` が載ることを確かめる（S5） | 運用作業 |
| S-4 | **言語指定の受け口は既存のものを使う（既定案）**。仕様の比較は下の 5-3-1。要件・サーバー設計に「クライアントは `ja` 固定で送る」ことと「この機能の API の応答は l10n を使わない（0 節 o）」ことを 1〜2 行書く | `Accept-Language` なら変更不要。`X-Language` を新設するなら 5-3-1 の右列を S2 に足す（Q-C9） |
| S-5 | 要件 `free-diamond-item.md` に、(a) 表示名の配信（`mst_item__l10n`）、(b) クライアントの `ja` 固定の言語指定、を追記する。**クライアントの設計は要件の確定を待たずに書いたので、食い違ったらこの文書を直す** | design-change の入口は Nexus 側（人） |
| S-6 | サーバー設計 `db.md`（`mst_item__l10n` の行）・`api.md`（言語の節）への追記 | S2 の文書の更新 |

名前の行が無い間は、クライアントは常にフォールバックの「無償ダイヤ」を出す。**クライアントだけ先に出しても壊れない**。

### 5-3-1. 言語ヘッダーの仕様（`X-Platform` との比較。S-4 の詳細）

`X-Platform`（要件 Q16・Q20〜Q24、home-player-info の S2 設計）を手本に並べた。**`Accept-Language` を使うなら中央の列のとおりでサーバーの変更は要らない**。`X-Language` を新設するなら右列を S2 に足す（人が Q-C9 で決める）。

| 項目 | `X-Platform`（手本） | `Accept-Language`（既存。既定案） | `X-Language` を新設する場合（既定案） |
| --- | --- | --- | --- |
| ミドルウェア | `ResolvePlatform`（エイリアス `platform`。`maintenance` のグループに付く） | `ResolveLanguage`（api グループの先頭。全 API） | `ResolveLanguage` を `X-Language` 優先で読む形に直す（無ければ `Accept-Language`、それも無ければ `ja`。Q-C9 の案 B） |
| `ApiSession` への保持 | `ApiSession::setPlatform` / `getPlatform` | `ApiSession::setLanguage` / `getLanguage`（と `setLocale`） | 同じ（変更なし） |
| 不正値・欠落 | HTTP 299 / `error_code` 99003 で拒否 | **拒否しない**。サポート外・欠落は既定 `ja` に倒す（言語は表示だけで、誤っても業務を壊さない） | 同左（拒否しない。`ja` に倒す） |
| 署名に含めるか | 含めない | 含めない（sign_up の署名は `timestamp:nonce:body`） | 含めない |
| 除外ルート（version・メンテなど） | `maintenance` グループの外（Toast の `/broadcasting/auth` など）は付けない・要求しない | **除外なし**（api グループ全体。version・メンテ中の 503 の応答でも `ja` が解決される） | 同左 |
| クライアントの付け方 | `ApiClient._build_headers()` で全 `request()` に付ける | 同じ位置で付ける（5-2） | 同じ位置・同じ方法でヘッダー名だけ `X-Language` |

追記: 要件・サーバー設計に「クライアントは `ja` 固定で送る」ことと「この機能の API の応答は l10n を使わない（0 節 o）」ことを 1〜2 行（新設する場合は上の列の内容と、`ResolveLanguage`・`AgentDocsInSyncTest` などのテスト・仕様書の直し）。

### 5-4. 確認事項

| # | 確認事項 | 既定案 |
| --- | --- | --- |
| Q-C7（確定） | サーバーに `mst_item__l10n` の行を足す作業をサーバー設計・要件へ追記する（design-change）。内容は 5-3 | 5-3 |
| Q-C9 | 言語のヘッダー名。案 A: **既存の `Accept-Language`**（標準。サーバーに受け口がある。変更不要）。案 B: 新設の `X-Language`（`X-Platform` と名前を揃える。サーバーの `ResolveLanguage` の直し・テスト・仕様書が要る） | **案 A**（人の補足「既存の言語ヘッダーがあればそれに合わせる」に従う）。B にする場合は 5-3 S-4 の右列をサーバー設計へ |
| Q-C8（確定） | クライアントの言語は `ja` 固定。HTTP ヘッダーで全 API に付ける（`X-Platform` と同じ場所・方法）。ヘッダー名は Q-C9（既定案 `Accept-Language`。サーバーに既存の受け口あり）。マスターの名前の引きも同じ値（`ApiConfig.language()`） | 5-2 |
| Q-C9 | 言語のヘッダー名: 既存の `Accept-Language`（既定案）か、新設の `X-Language` か | 5-4 |

## 6. テスト（GdUnit4。`make check-quiet` を通す）

| 対象 | 直す・足す内容 |
| --- | --- |
| `diamond_total_test.gd` | 暫定項のケース（「有償 30・暫定の無償 100・`free_diamond` 50 → 180」ほか）を直す。確かめるもの: ① 有償 30・`free_diamond` 50 → 80 ② `trx_diamond` が `{}`（null）で `free_diamond` 50 → 50 ③ `trx_diamond` だけ（`free_diamond` の行なし）→ 有償だけ ④ **`trx_diamond.free_amount` のキーがあっても足さない**（回帰。有償 7・`free_amount` 100 → 7）⑤ **`free_diamond` の行が `free_amount = 0` → 0**（有償だけ）⑥ `is_delete` が真・1 の行は除く（`trx_diamond`・`free_diamond` の行とも）⑦ `paid_amount` は足さない・`gold` など他の行は見ない（今のまま）⑧ 数値が浮動小数・null でも落ちない（今のまま） |
| `login_response_test.gd` | フィクスチャ `{"trx_diamond": {..., "free_amount": 100}}` から `free_amount` を外す（応答の形に合わせる）。`trx_diamond` が null・欠落・型違いで `{}` になる既存のテストはそのまま |
| `login_bonus.gd`（冒頭コメント） | `type` の値の例から `diamond` を外し、`item`（`free_diamond` は無償ダイヤ）と書く |
| `api_client_test.gd`・`api_config_test.gd` | `Accept-Language: ja` が `request()` の全リクエスト（認証なし・version・refresh を含む）に付き、`download()` に付かないこと（`X-Platform` のテストに倣う）。`ApiConfig.language()` が `ja` を返すこと（環境変数で変わらない） |
| `login_bonus_presenter_test.gd` | 偽の `MstItemRepository` で: `item` / `free_diamond` で名前が引けた → 「`<name>` x100」、**引けない（null・`name` 空）→ 「無償ダイヤ x100」**、他の `item` は名前が引ければ「`<name>` x…」・引けなければ従来の「アイテム (ID:…)」、`diamond` は未知の種別としてそのまま出る、を足す。`LoginBonus.is_free_diamond()` の単体テスト（`type` が `item` でも `id` が違う・`id` が `free_diamond` でも `type` が違う → 偽） |
| `local_mst_item_repository_test.gd`（新規。`local_mst_config_repository_test.gd` に倣う） | `mst_item` と `mst_item__l10n` を持つテスト用 SQLite で（`LocalMstItemRepository.new(database, "ja")`）: 行と `ja` の名前が引ける、別言語の行しか無い → `name` 空、`mst_item` に行が無い → null、DB が無い・テーブルが無い → null（例外にしない）、NULL の列は既定値 |
| `get_login_bonus_displays_use_case_test.gd`（新規） | `item` だけ名前を引く（`unit` などは引かない）、引けない・空は `item_name` 空、Repository が null でも落ちない |
| `home_use_cases_test.gd`・`home_presenter_test.gd` | フィクスチャは `free_diamond` の行だけで、変更不要の見込み。通ることを確かめる。合計が「有償 + `free_diamond`」になる 1 ケース（`trx_diamond` あり・`free_diamond` あり）を足す |
| e2e | `debug/e2e_driver.gd` は**変更しない**（`E2E_RESULT` に `diamond=` は既にある。home-player-info 8-2）。ログインボーナスの表示は録画の画面で確かめる |
| `make check-deps`・`make check-release` | `login` → `master_data/domain` の依存は許可（architecture.md）。新規ファイルの分類の変更は要らない見込み。通すだけ |

## 7. ドキュメント更新（実装 S5 で行う。ここでは一覧だけ）

| ファイル | 直す内容 |
| --- | --- |
| `.claude/api.md`（ヘッダーの表） | `Accept-Language: ja`（送信。全 `request()`、`download()`・Toast には付けない。値は `ApiConfig.language()` の固定 `ja`。サーバーの `ResolveLanguage` が解釈）を足す |
| `.claude/api.md` | Resource タイプ一覧: `diamond` の行を削除し、`item`（`free_diamond` は無償ダイヤ。`id` で見分ける）を明記。login の `trx_diamond` に「`free_amount` は無い。無償は `trx_item_list` の `free_diamond`」。`updated_resources` と購入応答について 4 節の注意書き（今は読まない・将来の前提） |
| `.claude/README.md` | login の取得項目の例（`trx_diamond` の例から `free_amount` が有れば外す） |
| `contexts/login/domain/entities/login_bonus.gd` | 冒頭コメントの `type` の例（`diamond`）を直す（C2 と同時） |
| `docs/MASTER_DATA.md` | `mst_item` を配信から読む（同梱しない。`REQUIRED_TABLES` に入れない）。Repository の使い方の例（5-1） |
| `.claude/implementation-history.md` | この機能の実装を追記 |
| `docs/design/home-player-info/client_design.md` | 4-2 の暫定の項の記述を、この設計の 2 節に合わせて直す（merged の設計の追従。要件の「ダイヤは暫定表示」の文言は Q14 のとおり Nexus 側で直す） |
| `docs/design/title-to-home/client_design.md` | login_bonus の `type` の一覧など、`diamond` に触れる記述があれば追従（S5 で確認） |

仕様書の食い違いとして報告するもの: Nexus の全体設計 K3 と要件 F3 は「`total_free_diamond_amount` は残高を返す」だが、サーバー設計 api.md 5.3 は購入応答から `total_*` を外した（人の決定）。クライアントの設計は後者（サーバー設計が正）に従う。Nexus の md の追従は人（親）に依頼する。

## 8. 確認手順（S5 で動画に撮る操作と期待結果）

### 8-1. 前提

- サーバー: `NexusMobileGameServer-Laravel` で `make up`。**free-diamond-item の S3（実装）が完了していること**（`trx_diamond.free_amount` の廃止、`login_bonus_list` の `item` / `free_diamond`）。`make migrate-fresh && make seed`（create マイグレーションの書き換えなので作り直し。db.md）。
- **マスター配信（名前を引くための前提。5-3）**: `mst_item__l10n` に `free_diamond`（`ja`・「無償ダイヤ」）の行がある（サーバーの別タスク・Q-C7）ことを確認し、`/master-import/export` で配信を作り直して、version API の `master.tables` に `mst_item` が載ることを確かめる。**クライアントはタイトルでマスターをダウンロードして切り替えた後にホームまで進む**（ケース 1 の動画はそれを映す。ダウンロードの進捗表示が出る）。
- クライアント: 縦長 1080x1920。録画は `godot --path <client> --write-movie <out.avi> --fixed-fps 30 --resolution 1080x1920 -- --e2e-case=<名前> --e2e-dwell=2 --e2e-home-hold=3`（`docs/workflow/recording.md`）。
- 値の作り方: 開発 DB のプレイヤーのシャード（`trx1`〜）の `trx_item`（`mst_item_id = 'free_diamond'`）・`trx_diamond` を直接更新する（home-player-info 8-1 と同じ。S5 で実際に通る SQL を確認する）。
- 新規ユーザー（sign_up は IP あたり 10 回/時間）は、ログインボーナス画面の名前を撮るケース 1・10・11・12 の 4 回（1 日目を受け取るため新規が要る）。ほかのケース（2〜8）は、ケース 1 で作ったプレイヤーの DB を書き換えて `--e2e-reset` なしで使い回す。
- **ログインボーナスの量（確認済み。`MstLoginBonusSeeder.php:37-43`）**: 1 日目 `free_diamond` 100、3 日目 100、6 日目 `diamond`/`diamond` 20000、7 日目 500。サーバーの S3 で 1・3・6・7 日目はすべて `item` / `free_diamond` に直る（量は不変）。新規サインアップ直後は 1 日目を受け取るので、ケース 1 のダイヤは 50 + 100 = 150。
- **ログインボーナスは 1 日 1 回**。ケース 2 以降の「起動」は受け取りなしで、ログインボーナス画面は空配列の文言（「本日のログインボーナス\nは受け取り済みです」。`build_text`）になる。別日（3・6・7 日目）の表示を撮るには `trx_login_bonus` を巻き戻す手順が要る（Q-C5）。
- 言語: クライアントが `Accept-Language: ja` を送っていることは、単体テスト（6 節）と、サーバーのリクエストログ（あれば）で確かめる。この機能の応答は l10n を使わないので、動画では見えない。
- 期待結果は画面の文字列と `E2E_RESULT` の `diamond=` で確認し、動画から 1 枚ずつ抜いて見る。

### 8-2. サーバーの前提状態と録画用シード（Server 側の別タスク）

動画に撮りたい「前提状態」（有償を持つプレイヤー、`trx_diamond` が無い、無償 0 の行が残る）は、**通常の開発シードでは作れない**。2 つの作り方がある。

| 方法 | 内容 | 既定案 |
| --- | --- | --- |
| A. DB を直接更新（上の 8-1） | 撮影のたびに SQL で前提を作る。手順をこの文書のケースの表に書く | **S5 ではこれで撮る**（サーバーの追加作業が要らない） |
| B. 録画用シード | `RecordingLoginBonusSeeder`（mst。1・3・6・7 日目を `item` / `free_diamond` に直す。db.md 6.1・api.md 8 節）に加え、**ケース 2〜5 のプレイヤー（有償を持つ・`trx_diamond` なし・無償 0 など）を作るシード**を足す | **Server 側の別タスク**として依頼する（要否は人が決める）。無ければ A で足りる |

### 8-3. ケース

| # | 前提状態 | 操作 | 期待結果 |
| --- | --- | --- | --- |
| 1 | 新規サインアップ直後（`--e2e-reset`）。規約なし。1 日目のログインボーナスは `free_diamond` 100 | 起動 → 自動 → ログインボーナス画面 → ホームで `--e2e-home-hold` | **ホームのダイヤは「150」**（有償 0 + 無償 50 + 100）。ログインボーナス画面の行は **「無償ダイヤ x100」**（マスターの名前。「アイテム (ID:free_diamond)」にならない・旧表示「ダイヤ」ではない。**マスターの名前とフォールバックは同じ文言なので、マスターから引いていることはケース 10 で確かめる**）。DB は `trx_item` に `free_diamond` の 1 行（`free_amount = 150`）、`trx_diamond` は `paid_amount = 0` で `free_amount` の列が無い |
| 2 | **有償を持つプレイヤー**: ケース 1 のプレイヤーの `trx_diamond.paid_amount` = 30、`free_diamond` の `free_amount` = 20 にする | 起動 | **ダイヤ「50」**（30 + 20）。暫定項があった頃の合計（`free_amount` 列の分）は無い。ログインボーナス画面は受け取り済みの文言 |
| 3 | **`trx_diamond` が null**: そのプレイヤーの `trx_diamond` の行を削除（サインアップで作られるので通常は無い状態）。`free_diamond` = 20 | 起動 | login が成功しクラッシュしない。**ダイヤ「20」**（有償 0 + 無償 20）。コイン・名前など他の項目は出る。ログインボーナス画面は受け取り済みの文言 |
| 4 | **無償 0 の行が残る**: `trx_diamond.paid_amount` = 30、`free_diamond` の `free_amount` = 0（行は残す。ガチャ・交換で使い切った後の状態） | 起動 | **ダイヤ「30」**。0 の無償行があっても落ちず、有償だけが出る。ログインボーナス画面は受け取り済みの文言 |
| 5 | **無償 0・有償 0**（`free_diamond` = 0、`paid_amount` = 0） | 起動 | **ダイヤ「0」**（「-」ではない。未ログインの「-」と区別する）。ログインボーナス画面は受け取り済みの文言 |
| 6 | **他 platform の有償**: `Google` の `trx_diamond` の行に `paid_amount` = 999。端末は `Apple` | 起動（`NEXUS_PLATFORM=Apple`） | 999 は出ない（応答は端末の行だけ）。ケース 2 と同じ値のまま。ログインボーナス画面は受け取り済みの文言 |
| 7 | **消費のあと**（サーバー側の操作。クライアントにガチャ・交換の画面は無い）: ケース 2 の再実行。実 API（`curl` で認証トークン・冪等キー付きのガチャ・交換）でダイヤのコスト 40 を消費できれば、ケース 2 の状態（無償 20・有償 30）から消費する（無償 20 → 0、有償 30 → 10。無償が先）。難しければ DB を同じ結果（無償 0・有償 10）に更新する（S5 で判断。DB 更新ならケース 2・4 に統合し、独立したケースにしない） | 再起動（login のしなおし） | ダイヤ **「10」**（50 − 40）。ログインボーナス画面は受け取り済みの文言。DB 更新で代替したときは、PR に「消費の経路は未確認」と書く |
| 8 | 桁数: `free_diamond` = 999,999,999 | 起動 | はみ出し・切れがない（省略記号。home-player-info 1-2）。桁区切りあり。ログインボーナス画面は受け取り済みの文言 |
| 10 | **名前がマスターから出る**: 新規ユーザー。サーバーの `mst_item__l10n` の `free_diamond`（`ja`）の `name` を、区別できる文字（例「無償ダイヤ（確認用）」）に更新して再エクスポートする（**確認後に元へ戻して再エクスポート**） | 起動 → タイトルでマスターの更新 → ログインボーナス画面 | 行が **「無償ダイヤ（確認用） x100」**（フォールバックの「無償ダイヤ」ではない）。マスターを引いている証拠 |
| 11 | **`MstItem` に名前の行が無い**: 新規ユーザー。`mst_item__l10n` の `free_diamond` の行を削除して再エクスポート（`mst_item` の行は残す）。**元に戻して再エクスポート** | 起動 → ログインボーナス画面 | **クラッシュせず「無償ダイヤ x100」**（フォールバック）。`item_name` 空の経路。ホームのダイヤは 150 のまま |
| 12 | **マスターが取得できない**（home-player-info のケース 7 と同じ再現）: 新規ユーザー。端末の `user://master/`・`master_state.json` を消し、`NEXUS_MASTER_BASE_URL=http://localhost:9` で起動する | 起動 → ログインボーナス画面 | タイトルで「マスターデータを更新できませんでした…」（既知）。同梱 DB に `mst_item` が無いので、**クラッシュせず「無償ダイヤ x100」**（フォールバック）。ホームのダイヤは 150 |
| 9 | **旧形式の応答の無視**（単体テストで確かめ、動画には撮らない）: `trx_diamond` に `free_amount` が付いた応答 | 単体テスト | 合計に足されない（6 節 ④） |

単体テスト（6 節）で確かめるもの: `DiamondTotal` の各状態、`LoginBonus.is_free_diamond()`、`LoginBonusPresenter` の表示文字（名前あり・なし・他の `item`）、`LocalMstItemRepository`（行あり・l10n なし・テーブルなし）、`GetLoginBonusDisplaysUseCase`。名前が `free_diamond` 以外の `item`（Q-C6）に出るかは、サーバーに他のアイテムの l10n 行が入っていれば動画に足し、無ければ単体テストだけにする。

## 9. 未解決点

### 確認事項（人が決める。既定案つき）

| # | 内容 | 既定案 |
| --- | --- | --- |
| Q-C1・Q-C2（**人の回答で確定**） | 表示文言は「無償ダイヤ」（ログインボーナスの行は「無償ダイヤ x100」）。名前は `mst_item`（l10n）から引き、引けないときのフォールバックも「無償ダイヤ」 | 3-2・5 節に反映済み |
| Q-C6（確定） | `free_diamond` 以外の `item` も `mst_item` から名前を引く | 3-2・3-4 |
| Q-C7（確定） | サーバーに `mst_item__l10n` の行を足す作業をサーバー設計・要件へ追記する（design-change）。内容は 5-3（申し送り） | 5-3 |
| Q-C8（確定） | クライアントの言語は `ja` 固定。`Accept-Language: ja` を全 API に付ける。マスターの名前の引きも同じ値（`ApiConfig.language()`）。**サーバーの受け口は既にある（新設不要）** | 5-2 |
| Q-C3・Q-C4・Q-C5（**既定案どおり確定**） | Q-C3: 前提状態は DB の直接更新で作る（録画用シードは Server 側の別タスク。要否は人が決める）。Q-C4: `total_*` はサーバー設計（api.md 5.3）に従い、クライアントは読まない。Nexus の全体設計・要件の追従（K3・F3・U-5）は人に依頼する。Q-C5: 別日のログインボーナスの表示は撮らず、単体テストで確かめる | 8-2・4 節・8-1 |

### 仮置き（既定案で進める）

| # | 内容 | 場所 |
| --- | --- | --- |
| P1 | `trx_diamond.free_amount` は、キーが来ても**無視する**（足さない） | 2 節 |
| P2 | ログインボーナスの判定は `LoginBonus.is_free_diamond()`（`login` コンテキスト内。`player` の定数に依存しない）。表示用の値は新しい UseCase `GetLoginBonusDisplaysUseCase`（既存の `GetLoginBonusesUseCase` は変えない） | 3-2・3-3 |
| P2b | `mst_item` は必須テーブルにしない・同梱しない（`mst_config` と同じ）。名前は画面を開くとき 1 回だけ読む | 5-1・3-3 |
| P3 | `type = diamond` は特別扱いせず未知の種別として出す（互換なし） | 3-2 |
| P4 | `updated_resources`・購入応答を読む仕組みは作らず、将来の前提を `.claude/api.md` に注意書きするだけ。`trx_item_list` のマージ方式は読む機能の設計で決める | 4 節 |
| P5 | e2e ドライバーは変更しない | 6 節 |
| P7 | `ApiConfig.language()` は定数 `ja`（環境変数・`project.godot` で上書きしない）。言語ヘッダーは `X-Platform` と同じ位置で全 `request()` に付ける（名前は定数 `LANGUAGE_HEADER`。既定 `Accept-Language`）。`MstItem` の言語も同じ値 | 5-2 |
| P6 | サーバーの S3 と同時にリリース（旧版互換なし。サーバーだけ先に出ても、旧クライアントは暫定項 `free_amount` が無くて 0 になるだけで合計は崩れず、`trx_item` の分は見える。ログインボーナスは「ダイヤ」でなく「アイテム (ID:free_diamond)」と出る） | 1 節 |

### 実行で確かめる点

| # | 内容 | 状況 |
| --- | --- | --- |
| E0 | `mst_item` と `mst_item__l10n` が配信に載り、クライアントが `mst_item` の SQLite を開いて `name` が引ける（同じ SQLite ファイルに l10n が入る） | Q-C7 の対応後、ケース 10。載らなければサーバーの運用作業 |
| E1 | login 応答の `login_bonus_list` が `type = item`・`id = free_diamond` で来る | S3 の完了後、ケース 1 |
| E2 | login 応答の `trx_diamond` に `free_amount` が無い・行が無いとき `null` | S3 の完了後、ケース 1・3 |
| E3 | ログインボーナス 1 日目の報酬の種類と量 | **解決済み**: `free_diamond` 100（`MstLoginBonusSeeder.php:37-43`）。ケース 1 は 150 |
| E4 | ケース 7 の消費を API で起こせるか | S5 で確認。難しければ DB 更新で代替 |
| E5 | `make check-quiet` が通る（`check-deps`・`check-release` を含む） | S5 |
