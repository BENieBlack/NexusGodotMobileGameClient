## 段の ID から、マスター（周期の日数と全日の報酬）を引いて LoginBonusStageMaster にする窓口。
##
## 目的: login が master_data の 2 つの Repository（通常・VIP）の細部（エンティティの列・日の補完）を
##       知らずに、画面に使える形のマスターを得る（client_design.md 2-1。master_data は読み取りのみ）。
## 流れ（read）:
##   1. 進捗の段があるときだけ、その mst_id でマスターを引く（段が無い側は引かない）
##   2. 引けたら、報酬行を LoginBonusStageMaster に直す（build_stage）:
##        day が 1〜cycle_days の範囲外（カムバック用の day = 0 を含む）の行は捨てる
##        content_type が空の行は捨てる（警告）。未知の content_type は捨てない（画面が unknown の絵で出す）
##        数量は content_quantity × amount。通常の行の is_paid が真なら metadata に is_paid: true を足す
##        1..cycle_days のうち行が無い日は空の日として補う
##        日の中の並びは Repository の SQL の並び（sort_desc 降順）のまま。ここで並べ替えない（D2）
##   3. 引けない（行が無い・読めない）段は null と種別を結果に残す。再取得の判断は UseCase が行う
class_name LoginBonusStageMasterReader
extends RefCounted

var _normal_repository: MstLoginBonusRepository
var _vip_repository: MstVipLoginBonusRepository


func _init(
	normal_repository: MstLoginBonusRepository, vip_repository: MstVipLoginBonusRepository
) -> void:
	_normal_repository = normal_repository
	_vip_repository = vip_repository


## calendars にある段のマスターを引く。段の mst_id が空なら引かない（引けない扱い）。
func read(calendars: LoginBonusCalendars) -> LoginBonusStageMasters:
	var masters := LoginBonusStageMasters.new()
	if calendars.normal != null:
		masters.has_normal_lookup = true
		if calendars.normal.mst_id != "":
			var lookup := _normal_repository.find_by_id(calendars.normal.mst_id)
			masters.normal_status = lookup.status
			if lookup.bonus != null:
				masters.normal = _build_normal(lookup.bonus)
	if calendars.vip != null:
		masters.has_vip_lookup = true
		if calendars.vip.mst_id != "":
			var vip_lookup := _vip_repository.find_by_id(calendars.vip.mst_id)
			masters.vip_status = vip_lookup.status
			if vip_lookup.bonus != null:
				masters.vip = _build_vip(vip_lookup.bonus)
	return masters


func _build_normal(bonus: MstLoginBonus) -> LoginBonusStageMaster:
	var entries: Array[Dictionary] = []
	for content in bonus.contents:
		var metadata: Dictionary = content.content_option.duplicate()
		if content.is_paid:
			metadata["is_paid"] = true
		entries.append(
			_entry(
				content.day,
				content.content_type,
				content.content_mst_id,
				content.total_quantity(),
				metadata
			)
		)
	return build_stage(bonus.loop_days, entries)


func _build_vip(bonus: MstVipLoginBonus) -> LoginBonusStageMaster:
	var entries: Array[Dictionary] = []
	for content in bonus.contents:
		entries.append(
			_entry(
				content.day,
				content.content_type,
				content.content_mst_id,
				content.total_quantity(),
				content.content_option.duplicate()
			)
		)
	return build_stage(bonus.loop_days, entries)


static func _entry(
	day: int, type: String, id: String, quantity: int, metadata: Dictionary
) -> Dictionary:
	return {"day": day, "type": type, "id": id, "quantity": quantity, "metadata": metadata}


## 報酬行（{day, type, id, quantity, metadata}。SQL の並びのまま）から段のマスターを作る。
## cycle_days が表示できる範囲（1〜8）でないときは days を作らない（画面全体を文字に落とす対象）。
static func build_stage(cycle_days: int, entries: Array[Dictionary]) -> LoginBonusStageMaster:
	var stage := LoginBonusStageMaster.new(cycle_days)
	if not stage.is_displayable():
		return stage
	# --- 1..cycle_days の空の日を用意する（行の無い日を補う）---
	for day in range(1, cycle_days + 1):
		stage.days.append(LoginBonusCalendarDay.new(day))
	# --- 行を日ごとに積む（範囲外・種別が空の行は捨てる）---
	for entry in entries:
		var day: int = entry["day"]
		if day < 1 or day > cycle_days:
			continue
		var type: String = entry["type"]
		if type == "":
			push_warning("ログインボーナスの報酬行の content_type が空のため捨てました（day=%d）" % day)
			continue
		var reward := LoginBonus.new(
			"", type, entry["id"], entry["quantity"], "", entry["metadata"]
		)
		stage.days[day - 1].rewards.append(reward)
	return stage
