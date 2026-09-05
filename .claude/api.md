# サーバAPI通信仕様

## 基本情報

- **ベースURL**: `http://localhost:8080/api`（開発環境）
- **コンテンツタイプ**: `application/json`

## 認証フロー

### 1. サインアップ（新規ユーザー）

**エンドポイント**: `POST /auth/sign_up`

**必須ヘッダー（HMAC-SHA256署名）**:
```
Content-Type: application/json
X-Client-Timestamp: {Unixタイムスタンプ（秒）}
X-Client-Nonce: {32文字以上のランダム文字列}
X-Client-Signature: HMAC-SHA256("{timestamp}:{nonce}:{request_body}")
```

**リクエストボディ**:
```json
{
  "device_id": "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx",
  "device_info": {
    "os": "Android",
    "os_version": "14",
    "model": "Pixel 8",
    "app_version": "1.0.0"
  }
}
```

**レスポンス**:
```json
{
  "token": {
    "access_token": "...",
    "refresh_token": "...",
    "expires_in": 3600
  },
  "sys_player": {
    "my_id": "...",
    "name": "...",
    "level": 1,
    "level_exp": 0,
    "vip_point": 0,
    "total_paid_amount": 0,
    "last_login_at": null
  },
  "sys_player_device": { ... },
  "sys_player_token": { ... }
}
```

### 2. サインイン（既存ユーザー）

**エンドポイント**: `POST /auth/sign_in`

署名ヘッダー不要。

**リクエストボディ**: サインアップと同じ形式

**レスポンス**: サインアップと同じ形式

### 3. ログイン（ゲームデータ取得）

**エンドポイント**: `POST /auth/login`

**必須ヘッダー**: `Authorization: Bearer {access_token}`

**レスポンス**:
```json
{
  "sys_player": { ... },
  "trx_unit_list": [
    { "trx_unit_id": 1, "mst_unit_id": 1, "grade": 1, "level": 1, "level_exp": 0, "is_delete": false }
  ],
  "trx_item_list": [
    { "mst_item_id": 1, "free_amount": 100, "paid_amount": 0, "is_delete": false }
  ],
  "trx_wallet_list": [
    { "mst_item_id": 1, "free_amount": 1000, "paid_amount": 0, "is_delete": false }
  ],
  "login_bonus_list": [
    {
      "unique_id": "uuid-v4",
      "type": "gold",
      "id": "gold",
      "amount": 100,
      "expire_at": null,
      "metadata": null
    }
  ]
}
```

### 4. トークンリフレッシュ

**エンドポイント**: `POST /auth/refresh_token`

**リクエストボディ**:
```json
{ "refresh_token": "..." }
```

**レスポンス**:
```json
{
  "token": { "access_token": "...", "refresh_token": "...", "expires_in": 3600 }
}
```

## エラーレスポンス

### HTTP 299（ビジネスエラー）
```json
{ "error_code": 1001, "message": "エラーメッセージ" }
```

### HTTP 503（メンテナンス）
```json
{
  "error": "Service Unavailable",
  "title": "メンテナンス中",
  "message": "メンテナンス中です",
  "start_at": "2026-01-01 00:00:00",
  "end_at": "2026-01-01 02:00:00"
}
```

## Resourceタイプ一覧（login_bonus_listのtypeフィールド）

| type | 説明 |
|------|------|
| `diamond` | ダイヤ（課金通貨） |
| `gold` | ゴールド（無課金通貨） |
| `stamina` | スタミナ |
| `unit` | ユニット |
| `equipment` | 装備 |
| `item` | アイテム |
