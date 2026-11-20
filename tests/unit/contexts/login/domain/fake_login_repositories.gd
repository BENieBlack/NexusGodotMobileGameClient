## LoginUseCase のテスト用の偽 Repository（API 側）。メモリのログインボーナス保持は本物を使う。
class_name FakeLoginRepositories
extends RefCounted


## 偽の login API。result を返し、渡された冪等キーを記録する。
class FakeLogin:
	extends LoginRepository
	var result: LoginDataResult = LoginDataResult.new()
	var keys: Array[String] = []

	func fetch_login(idempotency_key: String) -> LoginDataResult:
		keys.append(idempotency_key)
		return result


## 偽のカレンダー API。fetch / receive の結果を差し替えられ、呼び出しの引数を記録する。
class FakeCalendar:
	extends LoginBonusCalendarRepository
	var fetch_result: FetchLoginBonusCalendarsResult = FetchLoginBonusCalendarsResult.new()
	var receive_result: ReceiveVipLoginBonusResult = ReceiveVipLoginBonusResult.new()
	var fetch_count: int = 0
	## receive_vip に渡された {id, key}
	var receive_calls: Array[Dictionary] = []

	func fetch_calendars() -> FetchLoginBonusCalendarsResult:
		fetch_count += 1
		return fetch_result

	func receive_vip(id: String, key: String) -> ReceiveVipLoginBonusResult:
		receive_calls.append({"id": id, "key": key})
		return receive_result


## 偽の通常ログインボーナスのマスター。lookups は ID → MstLoginBonusLookup（無い ID は UNREADABLE）。
class FakeMstNormal:
	extends MstLoginBonusRepository
	var lookups: Dictionary = {}
	var asked: Array[String] = []

	func find_by_id(id: String) -> MstLoginBonusLookup:
		asked.append(id)
		return lookups.get(id, MstLoginBonusLookup.new())


## 偽の VIP ログインボーナスのマスター。
class FakeMstVip:
	extends MstVipLoginBonusRepository
	var lookups: Dictionary = {}
	var asked: Array[String] = []

	func find_by_id(id: String) -> MstVipLoginBonusLookup:
		asked.append(id)
		return lookups.get(id, MstVipLoginBonusLookup.new())


## 偽のマスター同期。handle() の呼び出し回数を数え、結果の status を差し替えられる。
## on_handle があれば、結果を返す前に呼ぶ（「再取得でマスターが入る」の再現に使う）。
class FakeCheckMaster:
	extends CheckMasterDataUseCase
	var status: CheckMasterDataResult.Status = CheckMasterDataResult.Status.UPDATED
	var call_count: int = 0
	var on_handle: Callable = Callable()

	func _init() -> void:
		super(null, null)

	func handle() -> CheckMasterDataResult:
		call_count += 1
		if on_handle.is_valid():
			on_handle.call()
		return CheckMasterDataResult.new(status)


## 本体（loop_days）と報酬行から、見つかった結果を作る（通常）。
## rows は {day, type, id, qty, amount, sort_desc, is_paid（任意）} の配列。
static func normal_lookup(id: String, loop_days: int, rows: Array = []) -> MstLoginBonusLookup:
	var bonus := MstLoginBonus.new()
	bonus.id = id
	bonus.loop_days = loop_days
	for row: Dictionary in rows:
		var content := MstLoginBonusContent.new()
		content.mst_login_bonus_id = id
		content.day = row["day"]
		content.content_type = row["type"]
		content.content_mst_id = row["id"]
		content.content_quantity = row.get("qty", 1)
		content.amount = row.get("amount", 1)
		content.is_paid = row.get("is_paid", false)
		content.sort_desc = row.get("sort_desc", 0)
		bonus.contents.append(content)
	return MstLoginBonusLookup.new(MstLookupStatus.Status.FOUND, bonus)


## VIP 版（is_paid は無い）。
static func vip_lookup(id: String, loop_days: int, rows: Array = []) -> MstVipLoginBonusLookup:
	var bonus := MstVipLoginBonus.new()
	bonus.id = id
	bonus.loop_days = loop_days
	for row: Dictionary in rows:
		var content := MstVipLoginBonusContent.new()
		content.mst_vip_login_bonus_id = id
		content.day = row["day"]
		content.content_type = row["type"]
		content.content_mst_id = row["id"]
		content.content_quantity = row.get("qty", 1)
		content.amount = row.get("amount", 1)
		content.sort_desc = row.get("sort_desc", 0)
		bonus.contents.append(content)
	return MstVipLoginBonusLookup.new(MstLookupStatus.Status.FOUND, bonus)
