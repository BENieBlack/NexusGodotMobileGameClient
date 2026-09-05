# SQLite マスターデータ管理

このプロジェクトでは、マスターデータをSQLiteデータベースで管理します。

## 必要なアドオン

Godot 4で SQLite を使用するには、以下のアドオンをインストールしてください：

### godot-sqlite (推奨)

**インストール手順:**

1. AssetLibrary から「SQLite」で検索
2. 「godot-sqlite」をダウンロード＆インストール
3. `Project > Project Settings > Plugins` で有効化

または、GitHubから直接ダウンロード:
https://github.com/2shady4u/godot-sqlite

**代替方法（手動）:**
```bash
cd addons
git clone https://github.com/2shady4u/godot-sqlite.git sqlite
```

## マスターデータベースの配置

SQLiteデータベースファイルは以下のディレクトリに配置してください：

```
res://data/master.db
```

## 使用方法

```gdscript
# MasterDataManagerを使用してマスターデータにアクセス
var gacha_list = MasterDataManager.get_gacha_repository().get_all_active()
for gacha in gacha_list:
    print(gacha.name)
```
