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
  テーブルごとに SQLite 生成                   master_data/ が全テーブルを
  SHA-256 ハッシュをファイル名に付与            開いて提供（MasterDatabase）
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

ハッシュが変わる = テーブルの内容が変わった、という意味になる。配信 URL は `/masterdata/<hash>/<ファイル名>`（ハッシュ名のディレクトリの下。version API の `url`）。

### auth/version APIとの連携

クライアントの実装は共有モジュール `master_data/`（`contexts/` と同階層。設計は `docs/design/title-to-home/client_design.md` 5 節）。呼び出し元はタイトル画面の最初の段階（認証の前）で、`master_data/domain/use_cases/check_master_data_use_case.gd`。

```
GET /api/auth/version?deploy_version=<現在持っているsys_deploy.id>
（認証不要・メンテナンス中も通る。X-Master-Hash があれば付ける）

レスポンス（更新あり）:
{
  "needs_update": true,
  "sys_deploy_id": 5,
  "master": {
    "tables": {
      "mst_item":  { "hash": "a3f8c1d2...", "url": "/masterdata/<hash>/<file>" },
      ...
    }
  }
}
```

項目の正はサーバーの `docs/design/title-to-home/api.md`。`url` は `/` 始まりなら配信ホスト（`ApiConfig.master_base_url()`。既定 `http://localhost:8091`。ADR 0001）を前置し、`http` 始まりの絶対 URL ならそのまま使う。

クライアントの処理フロー：
```
1. GET /auth/version を呼ぶ（失敗したら FAILED。止めずに続行して通知する）
2. needs_update: false → UP_TO_DATE（そのまま起動）
3. needs_update: true  → tables を走査
   - 保存のハッシュ（user://master_state.json）と比べ、違う・ファイルが無いテーブルだけ DL
   - DL は .tmp に書いてから rename で確定する
   - 全テーブルの取得後に、ハッシュと deploy_id を保存して DB を切り替える（途中で失敗したら旧 DB のまま）
4. 切り替え後に現行ハッシュ以外の古いファイルを消し、master_data_loaded を出す
```

起動後にサーバーのマスターが更新されたときは、HTTP 200 の応答に付く `X-Master-Update-Required` を `ApiClient` が検出し、`EventBus.master_update_required` 経由で裏の同期が 1 本だけ走る。

### ローカルストレージ構造

```
user://
├── master/                              # テーブル別SQLiteファイル（ハッシュ付き）
│   └── ...
└── master_state.json                    # deploy_id・master_hash・テーブルごとの現在ハッシュ（1 ファイル）
```

起動時は、保存済みの更新 DB が全部そろっていればそれを開く。無い・欠けたときはアプリ同梱の `data/master.db` から始める。

---

## 📁 ディレクトリ構造

```
NexusMobileGameClient-Godot/
├── data/
│   └── master.db                    # 同梱マスターデータベース（SQLite。初回・更新 DB が欠けたとき用）
└── master_data/
    ├── domain/
    │   ├── entities/                # MstUnit / MstEquipment / MstGacha（読み取りモデル）、MasterVersion など
    │   ├── repositories/            # 契約（MstUnitRepository など、MasterStorageRepository）
    │   └── use_cases/               # CheckMasterDataUseCase（同期）、CheckMasterDataResult
    └── data/
        ├── api/                     # version 応答の型
        ├── local/                   # MasterDatabase（SQLite 接続）
        └── repositories/            # LocalMstUnitRepository など、MasterDataApiRepository、LocalMasterDataRepository
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

### 3. オートロードの確認

マスターデータ専用のオートロードは無い。`AppContext`（依存の組み立て。`project.godot` の `[autoload]` の 2 番目）が `master_data/` の Repository と UseCase を作る。

```ini
[autoload]
EventBus="*res://core/domain/event_bus.gd"
AppContext="*res://app/app_context.gd"
```

## 📖 使用方法

### マスターデータの読み取り

mst の Repository は `AppContext` から受け取る（presenter / UseCase が使う。`contexts/*` は `master_data/domain` の公開型だけを参照でき、`master_data/data` は参照しない）。メモリのキャッシュは持たず、毎回 SQLite から読む（DB が更新 DB に切り替わっても古い値が残らないため）。読み取りは `get_all()` と `get_by_id()`。

```gdscript
# ガチャ
var gachas := AppContext.mst_gacha_repository().get_all()
var gacha := AppContext.mst_gacha_repository().get_by_id("gacha_001")
if gacha != null:
    print("開催期間: ", gacha.start_at, " ~ ", gacha.end_at)

# ユニット（レアリティの高い順。同じなら id 昇順）
var units := AppContext.mst_unit_repository().get_all()
var unit := AppContext.mst_unit_repository().get_by_id("unit_001")

# プレイヤーレベル・設定値（mst_player_level / mst_config。ホームのスタミナ表示用）
# 同梱 DB には入れず、配信があるときだけ更新 DB から読む（REQUIRED_TABLES にも入れない）。
# 配信が無い・テーブルが無いときは null が返る（呼び出し側が「分からない」として扱う）
var level := AppContext.mst_player_level_repository().get_by_level(1)   # level.max_stamina
var config := AppContext.mst_config_repository().get_by_id("stamina_recovery_interval_seconds")
if config != null:
    print(config.value_as_int())   # value_type が int で整数に読めるときだけ。他は -1

# アイテム名（mst_item と l10n の mst_item__l10n。ログインボーナスの表示用）
# 同梱 DB には入れず、配信があるときだけ更新 DB から読む（REQUIRED_TABLES にも入れない。mst_config と同じ）。
# 言語は ApiConfig.language()（"ja" 固定。API の Accept-Language と同じ値）を AppContext が渡す。
# mst_item に行が無い・配信が無いときは null、l10n の行（指定言語）が無いときは name が空の MstItem
var item := AppContext.mst_item_repository().get_by_id("free_diamond")
if item != null and item.name != "":
    print(item.name)   # 例: 無償ダイヤ。引けなければ呼び出し側（login）が固定名などへ倒す

# 装備
var equipments := AppContext.mst_equipment_repository().get_all()
var equipment := AppContext.mst_equipment_repository().get_by_id("equip_001")
```

型（`MstUnit` など）の `type` / `element` / `rarity` は DB の文字列のまま（`"Attack"` / `"Fire"` / `"SSR"` など）。フィルタや計算（開催中か等）は読み取りモデルに持たず、使う側のコンテキストの UseCase が行う。

### 更新の完了を待つ

`CheckMasterDataUseCase` のシグナルで受ける。`download_progress(current, total, table_name)` は進捗表示（タイトルの「マスターデータを更新中 (n/m)」）、`master_data_loaded` は DB の切り替え完了。

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

### クライアント側の実装（TODO 2〜5 は実装済み）

バージョン確認・差分 DL・ハッシュ記録・DB の切り替え・進捗表示は `master_data/` に実装した（上の「auth/version APIとの連携」と `docs/design/title-to-home/client_design.md` 5 節）。旧実装の `MasterDataManager`（オートロード）と、そのコード例（`scripts/managers/master_data_manager.gd`、`user://master_hashes.json`）は廃止した。

---

## 📝 モデルクラス

`MstUnit` / `MstEquipment` / `MstGacha`（`master_data/domain/entities/`）は `RefCounted` の読み取りモデルで、サーバー（DB）の列をそのまま持つ。レアリティ・属性・タイプは文字列のまま（enum は持たない）。

| モデル | 主な項目 |
|--------|----------|
| `MstUnit` | `id` `deploy_key` `type` `element` `rarity` |
| `MstEquipment` / `MstGacha` | 各ファイルの冒頭コメントを参照 |

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
