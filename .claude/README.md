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

```
NexusGodotMobileGameClient/
├── scenes/                    # Godotシーン（UI + シーンロジック）
│   ├── title/                 # タイトル画面（認証 → ログイン）
│   ├── login_bonus/           # ログインボーナス表示画面
│   ├── home/                  # ホーム画面
│   └── api_test/              # APIデバッグテスト画面
├── scripts/
│   ├── managers/              # オートロードのグローバルマネージャー
│   │   ├── user_data_manager.gd   # 認証状態・ゲームデータ管理
│   │   ├── scene_manager.gd       # シーン遷移管理
│   │   └── master_data_manager.gd # マスターデータ管理
│   ├── services/              # 通信サービス
│   │   ├── api_client.gd      # 汎用APIクライアント（HTTP 299対応、自動リフレッシュ）
│   │   └── auth_service.gd    # 認証専用サービス（HMAC-SHA256署名）
│   ├── models/                # データモデル
│   │   ├── mst/               # マスターデータモデル
│   │   ├── sys/               # システムデータモデル
│   │   └── trx/               # トランザクションモデル
│   └── repositories/          # リポジトリ（マスターデータ取得）
├── addons/                    # Godotアドオン
├── data/                      # ローカルデータ（SQLiteなど）
└── docs/                      # ドキュメント
```

## ドキュメント構成

| ファイル | 説明 |
|---------|------|
| [language.md](./language.md) | **言語設定（日本語で対応）** |
| [architecture.md](./architecture.md) | アーキテクチャ設計 |
| [coding-standards.md](./coding-standards.md) | コーディング規約 |
| [api.md](./api.md) | サーバAPIとの通信仕様 |
| [implementation-history.md](./implementation-history.md) | **実装履歴** |

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
