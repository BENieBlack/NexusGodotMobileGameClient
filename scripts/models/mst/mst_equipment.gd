class_name MstEquipment
extends RefCounted

# 装備マスターモデル

enum EquipmentType { ATTACK, DEFENSE, SUPPORT }
enum Element { FIRE, WATER, WIND, EARTH, LIGHT, DARK }
enum Rarity { C, UC, R, SR, SSR, UR }

var deploy_key: int = 202601010
var id: String = ""
var type: EquipmentType = EquipmentType.ATTACK
var element: Element = Element.FIRE
var rarity: Rarity = Rarity.C
var attack: int = 0
var defense: int = 0
var hp: int = 0
var sort_desc: int = 0
var is_active: bool = true
var created_at: String = ""
var updated_at: String = ""

# 多言語データ（l10n）
var name: String = ""
var description: String = ""

# JSONからインスタンスを生成
static func from_json(data: Dictionary) -> MstEquipment:
	var equipment = MstEquipment.new()
	
	if data.has("deploy_key"):
		equipment.deploy_key = int(data["deploy_key"])
	if data.has("id"):
		equipment.id = str(data["id"])
	if data.has("type"):
		equipment.type = _parse_equipment_type(str(data["type"]))
	if data.has("element"):
		equipment.element = _parse_element(str(data["element"]))
	if data.has("rarity"):
		equipment.rarity = _parse_rarity(str(data["rarity"]))
	if data.has("attack"):
		equipment.attack = int(data["attack"])
	if data.has("defense"):
		equipment.defense = int(data["defense"])
	if data.has("hp"):
		equipment.hp = int(data["hp"])
	if data.has("sort_desc"):
		equipment.sort_desc = int(data["sort_desc"])
	if data.has("is_active"):
		equipment.is_active = bool(data["is_active"])
	if data.has("created_at"):
		equipment.created_at = str(data["created_at"])
	if data.has("updated_at"):
		equipment.updated_at = str(data["updated_at"])
	
	# 多言語データ
	if data.has("name"):
		equipment.name = str(data["name"])
	if data.has("description"):
		equipment.description = str(data["description"])
	
	return equipment

# 文字列からEquipmentTypeに変換
static func _parse_equipment_type(type_str: String) -> EquipmentType:
	match type_str:
		"Attack": return EquipmentType.ATTACK
		"Defense": return EquipmentType.DEFENSE
		"Support": return EquipmentType.SUPPORT
		_: return EquipmentType.ATTACK

# 文字列からElementに変換
static func _parse_element(element_str: String) -> Element:
	match element_str:
		"Fire": return Element.FIRE
		"Water": return Element.WATER
		"Wind": return Element.WIND
		"Earth": return Element.EARTH
		"Light": return Element.LIGHT
		"Dark": return Element.DARK
		_: return Element.FIRE

# 文字列からRarityに変換
static func _parse_rarity(rarity_str: String) -> Rarity:
	match rarity_str:
		"C": return Rarity.C
		"UC": return Rarity.UC
		"R": return Rarity.R
		"SR": return Rarity.SR
		"SSR": return Rarity.SSR
		"UR": return Rarity.UR
		_: return Rarity.C

# EquipmentTypeを文字列に変換
func get_type_string() -> String:
	match type:
		EquipmentType.ATTACK: return "Attack"
		EquipmentType.DEFENSE: return "Defense"
		EquipmentType.SUPPORT: return "Support"
		_: return "Attack"

# Elementを文字列に変換
func get_element_string() -> String:
	match element:
		Element.FIRE: return "Fire"
		Element.WATER: return "Water"
		Element.WIND: return "Wind"
		Element.EARTH: return "Earth"
		Element.LIGHT: return "Light"
		Element.DARK: return "Dark"
		_: return "Fire"

# Rarityを文字列に変換
func get_rarity_string() -> String:
	match rarity:
		Rarity.C: return "C"
		Rarity.UC: return "UC"
		Rarity.R: return "R"
		Rarity.SR: return "SR"
		Rarity.SSR: return "SSR"
		Rarity.UR: return "UR"
		_: return "C"

# インスタンスをDictionaryに変換
func to_dict() -> Dictionary:
	return {
		"deploy_key": deploy_key,
		"id": id,
		"type": get_type_string(),
		"element": get_element_string(),
		"rarity": get_rarity_string(),
		"attack": attack,
		"defense": defense,
		"hp": hp,
		"sort_desc": sort_desc,
		"is_active": is_active,
		"created_at": created_at,
		"updated_at": updated_at,
		"name": name,
		"description": description
	}

# 総合ステータス値を計算
func get_total_stats() -> int:
	return attack + defense + hp

# デバッグ用の文字列表現
func _to_string() -> String:
	return "MstEquipment(id=%s, name=%s, atk=%d, def=%d, hp=%d)" % [id, name, attack, defense, hp]
