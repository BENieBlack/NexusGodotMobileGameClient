# マスターデータ管理システム

Godot 4プロジェクトでSQLiteマスターデータベースを使用するための実装ガイド。

---

## 🏗️ 設計思想

### マスターデータ配信方式

本システムは**テーブル単位のSQLiteファイル配信**方式を採用する。

```
Server（Laravelツール）                    Client（Godot）
┌─────────────────────────┐               ┌──────────────────────────┐
│ mst DB（MySQL）         │               │ user://master/           │
│   mst_item              │               │   mst_item_{hash}.sqlite │
│   mst_unit              │  差分DLのみ    │   mst_unit_{hash}.sqlite │
│   mst_gacha             │ ──────────→  │   mst_gacha_{hash}.sqlite│
│   ...                   │               │   ...                    │
└─────────────────────────┘               └──────────────────────────┘
         ↓ エクスポート                              ↓ 結合して参照
  テーブルごとに SQLite 生成                   MasterDataManager が
  SHA-256 ハッシュをファイル名に付与            全テーブルを統合して提供
```

#### テーブル単位で分割する理由

1. **差分DLの効率化**
   - 変更があったテーブルのSQLiteのみDLする
   - 例: `mst_gacha` を更新しても `mst_unit` はDL不要
   - 全テーブルを1ファイルにまとめると毎回全量DLになり通信コストが高い

2. **ハッシュ = テーブル内容の同一性保証**
   - ファイル名に含まれるハッシュはそのテーブルの全行データのSHA-256
   - クライアントがローカルで持っているハッシュとサーバーのハッシュを比較し、
     不一致のテーブルだけDLする
   - 内容が同じならハッシュは常に同じなので冪等性が保証される

3. **バージョン管理がシンプル**
   - `auth/version` APIが各テーブルのハッシュと DL URL を返す
   - クライアントは「ローカルに持っているハッシュ ≠ サーバーのハッシュ」のテーブルだけ更新

#### ファイル命名規則

```
mst_{テーブル名}_{SHA-256ハッシュ}.sqlite

例:
  mst_item_a3f8c1d2...sqlite   ← mst_item テーブルの内容に基づくハッシュ
  mst_unit_7b9e4a11...sqlite
  mst_gacha_2d5f8c90...sqlite
```

ハッシュが変わる = テーブルの内容が変わった、という意味になる。

### auth/version APIとの連携

```
POST /api/auth/version
{ "deploy_version": <現在持っているsys_deploy.id> }

レスポンス（更新あり）:
{
  "needs_update": true,
  "sys_deploy_id": 5,
  "latest_deploy_key": 2026090501,
  "master": {
    "sys_deploy_master_id": 4,
    "tables": {
      "mst_item":  { "hash": "a3f8c1d2...", "url": "/masterdata/mst_item_a3f8c1d2....sqlite" },
      "mst_unit":  { "hash": "7b9e4a11...", "url": "/masterdata/mst_unit_7b9e4a11....sqlite" },
      "mst_gacha": { "hash": "2d5f8c90...", "url": "/masterdata/mst_gacha_2d5f8c90....sqlite" }
    }
  }
}
```

クライアントの処理フロー：
```
1. auth/version を叩く
2. needs_update: false → そのまま起動
3. needs_update: true  → tables を走査
   - ローカルのハッシュ記録（user://master_hashes.json）と比較
   - 不一致テーブルのみ URL から SQLite をDL
   - DL完了後 user://master/{table_name}_{hash}.sqlite に保存
   - ハッシュ記録を更新
4. MasterDataManager を初期化して各テーブルのSQLiteを開く
```

### ローカルストレージ構造

```
user://
├── master/                              # テーブル別SQLiteファイル
│   ├── mst_item_a3f8c1d2....sqlite
│   ├── mst_unit_7b9e4a11....sqlite
│   ├── mst_gacha_2d5f8c90....sqlite
│   └── ...
└── master_hashes.json                   # テーブルごとの現在ハッシュ記録
    {
      "mst_item":  "a3f8c1d2...",
      "mst_unit":  "7b9e4a11...",
      "mst_gacha": "2d5f8c90..."
    }
```

---

## 📁 ディレクトリ構造

```
NexusGodotMobileGameClient/
├── data/
│   └── master.db                    # マスターデータベース（SQLite）
├── scripts/
│   ├── models/
│   │   ├── sys/                     # システムデータモデル
│   │   │   ├── sys_player.gd
│   │   │   ├── sys_player_device.gd
│   │   │   └── sys_player_token.gd
│   │   ├── mst/                     # マスターデータモデル
│   │   │   ├── mst_gacha.gd
│   │   │   ├── mst_unit.gd
│   │   │   └── mst_equipment.gd
│   │   └── trx/                     # トランザクションデータモデル
│   │       ├── trx_unit.gd
│   │       ├── trx_equipment.gd
│   │       └── trx_gacha_history.gd
│   ├── managers/
│   │   └── master_data_manager.gd   # マスターデータ管理マネージャー
│   └── repositories/
│       ├── mst_gacha_repository.gd
│       ├── mst_unit_repository.gd
│       └── mst_equipment_repository.gd
```

## 🚀 セットアップ

### 1. SQLiteアドオンのインストール

Godot 4で **godot-sqlite** アドオンをインストールしてください。

**方法A: AssetLibraryから**
1. Godotエディタを開く
2. `AssetLib` タブを選択
3. 「SQLite」で検索
4. 「godot-sqlite」をダウンロード＆インストール
5. `Project > Project Settings > Plugins` で有効化

**方法B: GitHubから手動**
```bash
cd addons
git clone https://github.com/2shady4u/godot-sqlite.git sqlite
```

### 2. マスターデータベースの配置

`data/master.db` ファイルがプロジェクトルートに配置されていることを確認してください。

### 3. Autoloadの確認

`project.godot` に以下が追加されていることを確認：

```ini
[autoload]
MasterDataManager="*res://scripts/managers/master_data_manager.gd"
```

## 📖 使用方法

### マスターデータの読み込み

マスターデータは自動的に読み込まれます。読み込み完了を待つ場合：

```gdscript
func _ready():
    if MasterDataManager.is_initialized:
        _use_master_data()
    else:
        MasterDataManager.master_data_loaded.connect(_use_master_data)

func _use_master_data():
    print("マスターデータが利用可能です")
```

### ガチャマスターの取得

```gdscript
# 全ガチャを取得
var all_gachas = MasterDataManager.get_gacha_repository().get_all()
for gacha in all_gachas:
    print("ガチャ: ", gacha.name, " (", gacha.id, ")")

# 有効なガチャのみ取得
var active_gachas = MasterDataManager.get_gacha_repository().get_all_active()

# IDで取得
var gacha = MasterDataManager.get_gacha_repository().get_by_id("gacha_001")
if gacha != null:
    print("ガチャ名: ", gacha.name)
    print("開催期間: ", gacha.start_at, " ~ ", gacha.end_at)
```

### ユニットマスターの取得

```gdscript
# 全ユニットを取得
var all_units = MasterDataManager.get_unit_repository().get_all()

# レアリティでフィルタ
var ssr_units = MasterDataManager.get_unit_repository().get_by_rarity(MstUnit.Rarity.SSR)

# 属性でフィルタ
var fire_units = MasterDataManager.get_unit_repository().get_by_element(MstUnit.Element.FIRE)

# IDで取得
var unit = MasterDataManager.get_unit_repository().get_by_id("unit_001")
if unit != null:
    print("ユニット名: ", unit.name)
    print("レアリティ: ", unit.get_rarity_string())
    print("属性: ", unit.get_element_string())
```

### 装備マスターの取得

```gdscript
# 全装備を取得
var all_equipment = MasterDataManager.get_equipment_repository().get_all()

# 有効な装備のみ取得
var active_equipment = MasterDataManager.get_equipment_repository().get_all_active()

# レアリティでフィルタ
var ur_equipment = MasterDataManager.get_equipment_repository().get_by_rarity(MstEquipment.Rarity.UR)

# タイプでフィルタ
var attack_equipment = MasterDataManager.get_equipment_repository().get_by_type(MstEquipment.EquipmentType.ATTACK)

# IDで取得
var equipment = MasterDataManager.get_equipment_repository().get_by_id("equip_001")
if equipment != null:
    print("装備名: ", equipment.name)
    print("攻撃力: ", equipment.attack)
    print("防御力: ", equipment.defense)
    print("HP: ", equipment.hp)
```

## 🔄 マスターデータの更新

### 現在の実装方式

サーバーは親テーブル単位でSQLiteを生成します。`__l10n`テーブルは親テーブルと同じSQLiteファイルに含まれます。

```text
mst_unit_<hash>.sqlite
├── mst_unit
└── mst_unit__l10n
```

クライアントは`GET /api/auth/version`で取得したテーブルグループ別ハッシュを比較し、変更されたファイルだけをダウンロードします。

### 旧方式（移行前）

移行前はサーバー側で全テーブルをまとめたSQLiteを生成し、
クライアントに手動コピーしていた。

```bash
# サーバー側：運営ツール（tol）でインポート & エクスポート
# → tool/public/masterdata/master_{hash}.sqlite が生成される

# クライアント側（暫定）
cp path/to/master.db ./data/master.db
```

### 今後の改善予定

テーブル単位SQLite配信は実装済みです。さらなる通信量削減が必要になった場合は、
大容量テーブルへのレコード差分配信を検討します。

---

## 📋 差分配信の設計メモ

> テーブル単位SQLite配信への移行前に整理した設計メモです。

### TODO 1: サーバー側（Laravel）— テーブル単位SQLiteエクスポート対応

現状の `MasterDataExporter` は全テーブルを1ファイルにまとめている。
これをテーブルごとに分割し、各ファイルのハッシュを `sys_deploy_master_table`
テーブルに記録する形に変更する。

**変更内容:**

```
tool/app/Services/MasterDataExporter.php を修正:
  - 全テーブル1ファイル → テーブルごとに mst_{table}_{hash}.sqlite を生成
  - 各テーブルの全行データ SHA-256 ハッシュを計算

新テーブル sys_deploy_master_table を追加:
  - sys_deploy_master_id
  - table_name    VARCHAR(128)
  - hash          VARCHAR(64)
  - file_size     INT
  - PRIMARY KEY (sys_deploy_master_id, table_name)

VersionResponse を修正:
  - master.hash（全体ハッシュ）→ master.tables（テーブルごとのハッシュ + URL）に変更
```

### TODO 2: MasterDataManager — バージョンチェック & 差分DL

`scripts/managers/master_data_manager.gd` に以下を実装する。

```gdscript
# ---- 実装すべき処理 ----

# 1. auth/version API を叩く
#    POST /api/auth/version { deploy_version: <保存済みdeploy_id> }
#    レスポンスの master.tables を取得

# 2. ローカルのハッシュ記録（user://master_hashes.json）と比較
#    不一致テーブル = 更新が必要なテーブル

# 3. 更新が必要なテーブルの SQLite を DL
#    GET {url} → user://master/mst_{table}_{hash}.sqlite に保存
#    HTTPRequest ノードを使用（Godot 組み込み）

# 4. DL完了後にハッシュ記録を更新
#    user://master_hashes.json を書き込む

# 5. MasterDataManager を再初期化
#    各テーブルの SQLite を開き直す
```

**実装イメージ（GDScript）:**

```gdscript
## scripts/managers/master_data_manager.gd に追加

const HASHES_PATH = "user://master_hashes.json"
const MASTER_DIR  = "user://master/"

## バージョンチェックを行い、必要なテーブルのみDLして更新する
## title.gd の認証完了後に呼び出す
func check_and_update(deploy_version: int) -> void:
    # auth/version API を叩く（AuthService 経由）
    # レスポンスの master.tables を走査
    # _load_local_hashes() と比較
    # 不一致テーブルを _download_table_sqlite() でDL
    # _save_local_hashes() でハッシュ記録更新
    # _reload_all_tables() で再初期化
    pass

## ローカルのハッシュ記録を読み込む
## 戻り値: { "mst_item": "abc123...", "mst_unit": "def456...", ... }
func _load_local_hashes() -> Dictionary:
    if not FileAccess.file_exists(HASHES_PATH):
        return {}
    var file = FileAccess.open(HASHES_PATH, FileAccess.READ)
    return JSON.parse_string(file.get_as_text())

## ハッシュ記録を保存する
func _save_local_hashes(hashes: Dictionary) -> void:
    var file = FileAccess.open(HASHES_PATH, FileAccess.WRITE)
    file.store_string(JSON.stringify(hashes))

## テーブルの SQLite をサーバーからDLして user://master/ に保存する
## 完了シグナル: table_downloaded(table_name: String)
func _download_table_sqlite(table_name: String, url: String, hash: String) -> void:
    # HTTPRequest ノードを使用
    # DL先: user://master/mst_{table_name}_{hash}.sqlite
    pass

## 全テーブルの SQLite を開き直してリポジトリを再初期化する
func _reload_all_tables() -> void:
    # 各テーブル用の SQLite.new() を開く
    # リポジトリに渡す
    pass
```

### TODO 3: title.gd — バージョンチェックを起動フローに組み込む

```gdscript
## scenes/title/title.gd

func _on_login_completed(data: Dictionary) -> void:
    UserDataManager.set_login_data(data)
    
    # ★ TODO: ここでマスタデータのバージョンチェック & 差分DLを挟む
    # MasterDataManager.check_and_update(UserDataManager.deploy_version)
    #   → 完了シグナルを受けてからシーン遷移する
    
    SceneManager.goto_login_bonus()
```

### TODO 4: ローカルデータの初期化処理

初回起動時 or ハッシュ記録がない場合は全テーブルをDLする。
既存の `res://data/master.db`（アプリ同梱）はフォールバック用として残すか、
削除して完全にサーバーDL方式に移行するかを決定する。

```gdscript
# 判定ロジック案
if not DirAccess.dir_exists_absolute("user://master/"):
    DirAccess.make_dir_absolute("user://master/")
    # 全テーブルをDL（初回）
else:
    # ハッシュ比較して差分のみDL
```

### TODO 5: DL進捗の表示

大量テーブルのDL中はプレイヤーに進捗を見せる必要がある。
タイトル画面にローディングUIを追加する。

```gdscript
# 例: "マスターデータを更新中... (3/12)"
signal download_progress(current: int, total: int, table_name: String)
```

---

## 🔍 キャッシュ機構

各リポジトリはメモリキャッシュを持っており、2回目以降の取得は高速です。

```gdscript
# キャッシュをクリアして再読み込み
MasterDataManager.get_gacha_repository().clear_cache()
var fresh_data = MasterDataManager.get_gacha_repository().get_all()
```

## ⚙️ パフォーマンス最適化

- **起動時の一括読み込み**: `get_all()` を起動時に呼んでキャッシュをウォームアップ
- **必要な時のみ読み込み**: `get_by_id()` で個別にオンデマンド読み込み
- **フィルタリングはメモリ内**: SQLクエリではなくGDScriptでフィルタ

```gdscript
func _ready():
    # 起動時に全マスターデータをキャッシュ
    MasterDataManager.master_data_loaded.connect(_warmup_cache)

func _warmup_cache():
    MasterDataManager.get_gacha_repository().get_all()
    MasterDataManager.get_unit_repository().get_all()
    MasterDataManager.get_equipment_repository().get_all()
    print("マスターデータキャッシュのウォームアップ完了")
```

## 📝 モデルクラス

### Enumの使用例

```gdscript
# レアリティ
MstUnit.Rarity.C       # Common
MstUnit.Rarity.UC      # Uncommon
MstUnit.Rarity.R       # Rare
MstUnit.Rarity.SR      # Super Rare
MstUnit.Rarity.SSR     # Super Super Rare
MstUnit.Rarity.UR      # Ultra Rare

# 属性
MstUnit.Element.FIRE
MstUnit.Element.WATER
MstUnit.Element.WIND
MstUnit.Element.EARTH
MstUnit.Element.LIGHT
MstUnit.Element.DARK

# ユニット/装備タイプ
MstUnit.UnitType.ATTACK
MstUnit.UnitType.DEFENSE
MstUnit.UnitType.SUPPORT
```

## 🐛 トラブルシューティング

### SQLiteプラグインが見つからない

エラー: `SQLite plugin is not installed`

→ godot-sqliteアドオンをインストールして、プラグインを有効化してください。

### データベースファイルが見つからない

エラー: `Database file not found: res://data/master.db`

→ `data/master.db` ファイルがプロジェクトルートに存在することを確認してください。

### データが空

マスターデータが空の場合、サーバー側でSeederを実行してからSQLiteエクスポートを行ってください。

```bash
docker exec api-php php artisan db:seed --class=MasterDataSeeder --database=mst
```

## 📚 関連ドキュメント

- [godot-sqlite GitHub](https://github.com/2shady4u/godot-sqlite)
- [SQLite Documentation](https://www.sqlite.org/docs.html)
