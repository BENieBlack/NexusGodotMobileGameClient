# 実装履歴

## 2026-09-02

### 認証フローの修正・改善

**問題**: クライアントとサーバのレスポンスキーが不一致
- `auth_service.gd` が `data.dtoToken`・`data.sysPlayer` を期待していたが、サーバは `token`・`sys_player` を返していた

**修正内容**:

1. **`auth_service.gd`**: レスポンスキー修正 (`dtoToken` → `token`, `sysPlayer` → `sys_player`)
   - シグナル `auth_completed` に `refresh_token` 引数を追加

2. **`api_client.gd`**: 以下を追加
   - HTTP 299 ビジネスエラー対応（`business_error` シグナル）
   - アクセストークン自動リフレッシュ（HTTP 401 時に `POST /auth/refresh_token` を呼び再送）

3. **`user_data_manager.gd`**: 以下を追加
   - `refresh_token` フィールドの保存・復元
   - `update_tokens()` メソッド（リフレッシュ後のトークン更新用）
   - `set_login_data()` メソッド（ログインAPI後のゲームデータ保存用）
   - `trx_unit_list`, `trx_item_list`, `trx_wallet_list`, `login_bonus_list` フィールド

4. **`title.gd`**: 認証完了後に `POST /auth/login` を呼び出し、ゲームデータを取得してからログインボーナス画面へ遷移

5. **`login_bonus.gd`**: `UserDataManager.login_bonus_list` のデータを実際に表示（ダイヤ・ゴールド・ユニット等のリソースタイプに対応）

6. **`.claude/` ディレクトリ**: プロジェクトドキュメントを整備
   - `README.md`, `architecture.md`, `coding-standards.md`, `api.md`, `language.md`
   - `.opencode` を `.claude` へのシンボリックリンクとして設定

## 2026-11-12

### タイトル〜ホームの新構成への移行完了（S5 第 3 段）

設計: `docs/design/title-to-home/client_design.md`。サーバー設計（正）に合わせ、旧構成（`scenes/` と `scripts/`）を新構成（クリーンアーキテクチャ + 軽量 DDD。`architecture.md`）へ置き換えた。旧構成は削除済み。

1. **画面（presentation）**: 各画面を `contexts/<名前>/presentation/<画面>/` の `*.tscn` + `*_presenter.gd` に移した。presenter は UseCase だけを呼ぶ。
   - タイトル（`TitlePresenter`）: マスター確認 → 認証 → login を段階で直列に進め、失敗した段階から「再試行」。login が成功するまで先へ進まない（旧実装の「login 失敗でもホームへ進む」を廃止）。冪等キーは presenter が保持（`IdempotencyKey.can_reuse` で再利用か作り直しかを決める）
   - 規約（`AgreementPresenter`）: 未同意が無ければ画面を見せずにスキップ。取得失敗はスキップせずエラー + 再試行。同意は規約ごとの冪等キーで 1 件ずつ送り、失敗した規約から再試行
   - ログインボーナス: 通信せず `GetLoginBonusesUseCase` の一覧を表示（`grade` は metadata にあるときだけ）。ホーム: `GetPlayerIdUseCase`
   - エラー文言は `core/presentation/error_messages.gd`、表示は `error_view.gd` に共通化（429 は `retry_after` の間、再試行ボタンを無効にする）
2. **オートロードの整理**: `EventBus` → `AppContext` → `SceneRouter` → `Toast`（+ 開発専用の `E2EDriver`）。旧 `UserDataManager` / `SceneManager` / `AuthService` / `MasterDataManager` / `ToastManager` を廃止。`Toast` は Reverb 接続の認証情報を `connect_to_reverb(user_id, access_token)` で受け取る形に変えた（挙動は旧と同じ。ギルドの自動購読は新構成へ移るまで行わない）
3. **旧構成の削除**: `scenes/`・`scripts/`（managers / services / models / repositories / tests）を削除。`api_test` は `debug/api_test/`（`AppContext` の `ApiClient` を使う形に書き換え）
4. **改名**: `master_data/` の `Master*`（`MasterUnit` など）を `Mst*` に、規約の `PendingAgreement` を `SysAgreement` に
5. **e2e ドライバー**: `debug/e2e_driver.gd`（`--e2e-case` / `--e2e-reset` / `--e2e-fail-login` / `--e2e-corrupt-token` など）。通しの確認に使う
6. **ドキュメント**: README・architecture（移行完了）・api・MASTER_DATA.md を新構成に合わせて更新

実サーバー（`http://localhost:8090`）に対し、e2e ドライバーでタイトル → 認証 → login → 規約（未同意なしでスキップ）→ ログインボーナス → ホームの通しが最後まで動くことを確認した。

