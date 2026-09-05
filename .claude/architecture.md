# アーキテクチャ設計

## レイヤー構成

```
┌─────────────────────────────────────┐
│  Presentation Layer (scenes/)       │ ← UI・シーン遷移
├─────────────────────────────────────┤
│  Application Layer (managers/)      │ ← グローバル状態管理
├─────────────────────────────────────┤
│  Service Layer (services/)          │ ← API通信・認証
├─────────────────────────────────────┤
│  Data Layer (models/, repositories/)│ ← データモデル・取得
└─────────────────────────────────────┘
```

## オートロード（グローバルシングルトン）

| 名前 | スクリプト | 役割 |
|------|-----------|------|
| `UserDataManager` | `scripts/managers/user_data_manager.gd` | 認証トークン・プレイヤーデータ・ゲームデータ |
| `SceneManager` | `scripts/managers/scene_manager.gd` | シーン遷移 |
| `MasterDataManager` | `scripts/managers/master_data_manager.gd` | マスターデータ（SQLite） |

## 依存関係ルール

- `scenes/` → `managers/`, `services/` への参照はOK
- `managers/` → `services/` への参照はOK
- `services/` → `managers/` への参照はOK（`UserDataManager`のトークン参照）
- `models/` → 他への依存なし
- `repositories/` → `models/` のみ参照

## シーン構成

| シーン | パス | 説明 |
|--------|------|------|
| タイトル | `scenes/title/title.tscn` | 認証 → ログイン → ログインボーナスへ |
| ログインボーナス | `scenes/login_bonus/login_bonus.tscn` | ログインボーナス表示 |
| ホーム | `scenes/home/home.tscn` | メインメニュー |
| APIテスト | `scenes/api_test/api_test.tscn` | デバッグ用 |
