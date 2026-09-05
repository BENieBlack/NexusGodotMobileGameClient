# コーディング規約

## 言語・フレームワーク

- **言語**: GDScript (Godot 4)
- **命名規則**: snake_case（変数・関数・ファイル名）、PascalCase（クラス名）

## GDScript規約

### 変数・関数名

```gdscript
# ✅ Good: snake_case
var auth_token: String = ""
func get_user_data() -> Dictionary:

# ❌ Bad
var authToken: String = ""
func GetUserData() -> Dictionary:
```

### 型アノテーション

```gdscript
# ✅ Good: 型を明示する
var is_logged_in: bool = false
var auth_token: String = ""
func set_auth_data(access_token: String, p_refresh_token: String, data: Dictionary) -> void:

# ❌ Bad: 型なし
var is_logged_in = false
func set_auth_data(token, data):
```

### シグナル定義

```gdscript
# ✅ Good: 引数に型を付ける
signal auth_completed(access_token: String, refresh_token: String, user_data: Dictionary)
signal request_failed(error: String)
```

### コメント

```gdscript
# ✅ Good: 日本語でコメントを書く
# デバイスIDをリセット（新しいUUIDを生成）
func reset_device_id() -> void:

# HTTPリクエスト完了時のコールバック
func _on_request_completed(...) -> void:
```

## ファイル・ディレクトリ命名規則

| 対象 | 規則 | 例 |
|------|------|-----|
| GDScriptファイル | snake_case | `auth_service.gd`, `user_data_manager.gd` |
| シーンファイル | snake_case | `login_bonus.tscn` |
| ディレクトリ | snake_case | `login_bonus/`, `api_test/` |
| クラス名（class_name） | PascalCase | `MstGachaRepository` |

## Gitコミットメッセージ規約

```
<type>: <日本語の説明>

[任意の本文（日本語）]
```

### コミットタイプ
- `feat`: 新機能
- `fix`: バグ修正
- `refactor`: リファクタリング
- `docs`: ドキュメント
- `style`: コードスタイル
- `test`: テスト
- `chore`: ビルド・ツール関連

### 例

```
feat: ログインボーナス画面にサーバデータを表示

UserDataManager.login_bonus_listからリソースタイプ・量を取得して表示する。
ダイヤ・ゴールド・スタミナ・ユニット・装備・アイテムに対応。
```
