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

コメントは日本語で書く。目的は「処理の内容と流れ、そしてなぜそうしたかが、コードを追わなくても分かる」こと。

#### 基本の書き方

```gdscript
# ✅ Good: 日本語でコメントを書く
## デバイスIDをリセット（新しいUUIDを生成）
func reset_device_id() -> void:

## HTTPリクエスト完了時のコールバック
func _on_request_completed(...) -> void:
```

#### 規約

1. **ファイル冒頭**: 何のためのファイルか、全体の流れ（番号付きの手順）、使い方・入出力・終了コードを書く。設計の根拠（`.claude/architecture.md` の節など）を参照する
2. **関数・クラス**: GDScript は `##` のドキュメントコメント、Python は docstring。何をするか、引数、戻り値、失敗時の扱い（例外・エラー値）を書く。呼び出し側が知るべき前提も書く
3. **処理のかたまりごとに見出しコメント**: 長い関数は `# --- 1. 〜 ---` のように手順を番号で区切り、なぜその処理が要るのかを書く。流れが追えるようにする
4. **why を書く**: コードを日本語に言い換えるだけのコメント（`# i を 1 増やす`）は書かない。判断の理由、除外・例外・順序が重要な理由、落とし穴（Godot のバージョン依存、誤検出を避ける理由）を書く
5. **ルール・正規表現・マジックナンバー・固定値**: それが何で、なぜその値かを書く。正規表現は何にマッチさせたいかを具体例つきで書く
6. **データ構造**: 辞書やタプルの形（キーと意味）をコメントで示す
7. **テスト**: 各テストに「前提 → 操作 → 期待」を 1〜3 行で書く。なぜそのケースが必要か（どの違反・誤検出を守るか）も書く
8. **設定ファイル（Makefile・CI）**: 各ターゲット・各ステップの目的、依存関係、前提の環境変数、失敗時の挙動を書く
9. **更新**: コメントがコードと食い違ったら、コメントも直す。古くなる情報（行数、ファイル数）は書かない

#### 書き方の例（見出しコメントと why）

```gdscript
## 保存済みのトークンでログインし、失敗したら再ログインへ回す。
## 戻り値: 成功なら true。通信エラーは例外にせず false を返し、理由は error_message に入れる。
func try_login() -> bool:
	# --- 1. 保存済みのトークンを読む ---
	# 起動のたびに通信すると遅いので、まずローカルを見る

	# --- 2. 期限を確かめる ---
	# 期限切れのトークンでサーバーへ送ると 401 になり、再試行が 1 回無駄になるため先に弾く
```

#### 外部ライブラリ

`addons/` 配下は外部ライブラリなので、コメントを足さない。

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
