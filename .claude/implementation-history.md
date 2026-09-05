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
