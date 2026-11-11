# 開発ドキュメント / Development Documentation

このディレクトリには、Godotモバイルゲームクライアントの開発ルールとガイドラインが含まれています。

> **📌 重要**: このプロジェクトでは**日本語**でコミュニケーションを行います。詳細は [language.md](./language.md) を参照してください。

## プロジェクト概要

このプロジェクトは、**モバイルゲームのクライアントアプリ**を提供するGodot 4アプリケーションです。
バックエンドAPIは `NexusLaravelMobileGameServer` が提供します。

### 主な特徴

- **Godot 4**: GDScriptによる実装
- **デバイスIDベース認証**: HMAC-SHA256署名付きサインアップ、サインイン
- **自動トークンリフレッシュ**: アクセストークン期限切れ時に自動更新
- **レイヤード構成**: scenes / scripts(services, managers, models, repositories) の分離

## ディレクトリ構成

クリーンアーキテクチャ（presentation / domain / data の 3 層）+ 軽量 DDD。詳細は [architecture.md](./architecture.md)。下は移行後の構成で、既存ファイルは機能単位で順に移す（行き先は architecture.md 8 節）。

```
NexusGodotMobileGameClient/
├── app/                       # 合成ルート
│   ├── app_context.gd         #   依存の組み立て（オートロード）
│   └── scene_router.gd        #   画面遷移（オートロード）
├── core/                      # 共有カーネル
│   ├── domain/                #   Result, AppError, EventBus, JsonReader
│   ├── data/                  #   http/（ApiClient・ApiResult）, config/（ApiConfig）, storage/
│   └── presentation/          #   Toast, ローディング, エラーダイアログ
├── master_data/               # 読み取り専用の参照データ（コンテキストに属さない共有モジュール）
│   ├── domain/                #   mst の読み取りモデル、契約、同期 UseCase（バージョン確認・更新判定）
│   └── data/                  #   SQLite、差分ダウンロード、ハッシュ管理、mst Repository、version API
├── contexts/                  # サーバーの Domain/{Context} と同じ名前（master_data は含めない）
│   ├── auth/                  #   認証、タイトル画面
│   ├── agreement/             #   規約の取得・同意、規約画面
│   ├── login/                 #   login、ログインボーナス画面
│   ├── player/                #   プレイヤー・所持データ、ホーム画面
│   │   └── {presentation, domain(entities, use_cases, repositories), data(api, local, repositories)}
│   └── （今後: gacha / unit / equipment …）
├── tests/                     # core/・master_data/・contexts/ をミラー（unit / integration / e2e）
├── assets/                    # アセット
├── addons/                    # Godotアドオン
├── data/                      # ローカルデータ（SQLiteなど）
└── docs/                      # ドキュメント（design/<機能>/client_design.md）
```

> 現在は移行前で、`scenes/` と `scripts/`（managers / services / models / repositories）の旧構成が残っている。

## ドキュメント構成

| ファイル | 説明 |
|---------|------|
| [language.md](./language.md) | **言語設定（日本語で対応）** |
| [architecture.md](./architecture.md) | アーキテクチャ設計（3 層・コンテキスト・依存ルール・命名・移行方針） |
| [coding-standards.md](./coding-standards.md) | コーディング規約 |
| [api.md](./api.md) | サーバAPIとの通信仕様 |
| [implementation-history.md](./implementation-history.md) | **実装履歴** |
| `docs/design/<機能>/client_design.md` | 機能ごとのクライアント設計 |

## 📁 `.opencode/` について

`.opencode` は `.claude` へのシンボリックリンクです。
**ドキュメントの追加・修正は `.claude/` 側だけ行えば両方に反映されます。**

## サーバAPIとの通信フロー

### 起動フロー

```
アプリ起動
  ↓
タイトル画面
  ↓ 新規ユーザー: POST /api/auth/sign_up (HMAC-SHA256署名付き)
  ↓ 既存ユーザー: POST /api/auth/sign_in
  ↓ access_token / refresh_token 取得・保存
  ↓
POST /api/auth/login (Bearer認証)
  ↓ sys_player / trx_unit_list / trx_item_list / trx_wallet_list / login_bonus_list 取得
  ↓
ログインボーナス画面 → ホーム画面
```

### トークン管理

- **アクセストークン**: メモリ + ローカルファイル保存、有効期限1時間
- **リフレッシュトークン**: メモリ + ローカルファイル保存、有効期限30日
- **自動リフレッシュ**: `api_client.gd` が HTTP 401 を検知して `POST /api/auth/refresh_token` を自動呼び出し

### エラーハンドリング

| HTTPステータス | 意味 | 対応 |
|---------------|------|------|
| 200 | 成功 | 正常処理 |
| 299 | ビジネスロジックエラー | `business_error` シグナルで通知 |
| 401 | 認証エラー（トークン期限切れ） | 自動リフレッシュ → 再送 |
| 503 | メンテナンス中 | メンテナンス画面表示（未実装） |

## クイックスタート

### 1. Godotプロジェクトを開く

Godot 4 でこのディレクトリを開いてください。

### 2. サーバを起動

`NexusLaravelMobileGameServer` を起動してください（デフォルト: `http://localhost:8080`）。

### 3. エンドポイント設定

`scripts/services/auth_service.gd` と `scripts/services/api_client.gd` の `BASE_URL` 定数を環境に合わせて変更してください。

## 重要な設計原則

### 1. シーンとロジックの分離

- シーン（`.tscn`）はUI構造のみ
- シーンロジック（`.gd`）はUI制御とシグナル接続のみ
- ビジネスロジックは `scripts/services/` または `scripts/managers/` に実装

### 2. グローバルマネージャー（オートロード）

- `UserDataManager`: 認証状態・ゲームデータのシングルトン
- `SceneManager`: シーン遷移のシングルトン
- `MasterDataManager`: マスターデータのシングルトン

### 3. サーバAPIのレスポンス形式

サーバは以下の形式でレスポンスを返します：

```json
// sign_up / sign_in
{
  "token": { "access_token": "...", "refresh_token": "...", "expires_in": 3600 },
  "sys_player": { "my_id": "...", "name": "...", "level": 1, ... },
  "sys_player_device": { ... },
  "sys_player_token": { ... }
}

// auth/login
{
  "sys_player": { ... },
  "trx_unit_list": [...],
  "trx_item_list": [...],
  "trx_wallet_list": [...],
  "login_bonus_list": [
    { "unique_id": "...", "type": "gold", "id": "gold", "amount": 100, "expire_at": null, "metadata": null }
  ]
}
```

## 更新履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|---------|
| 2026-09-02 | 0.1.0 | 初期ドキュメント作成 |
