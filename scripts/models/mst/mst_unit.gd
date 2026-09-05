class_name MstUnit
extends RefCounted

# ユニットマスターモデル

enum UnitType { ATTACK, DEFENSE, SUPPORT }
enum Element { FIRE, WATER, WIND, EARTH, LIGHT, DARK }
enum Rarity { C, UC, R, SR, SSR, UR }

var deploy_key: int = 202601010
var id: String = ""
var type: UnitType = UnitType.ATTACK
var element: Element = Element.FIRE
var rarity: Rarity = Rarity.C
var created_at: String = ""
var updated_at: String = ""

# 多言語データ（l10n）
var name: String = ""
var description: String = ""

# JSONからインスタンスを生成
static func from_json(data: Dictionary) -> MstUnit:
	var unit = MstUnit.new()
	
	if data.has("deploy_key"):
		unit.deploy_key = int(data["deploy_key"])
	if data.has("id"):
		unit.id = str(data["id"])
	if data.has("type"):
		unit.type = _parse_unit_type(str(data["type"]))
	if data.has("element"):
		unit.element = _parse_element(str(data["element"]))
	if data.has("rarity"):
		unit.rarity = _parse_rarity(str(data["rarity"]))
	if data.has("created_at"):
		unit.created_at = str(data["created_at"])
	if data.has("updated_at"):
		unit.updated_at = str(data["updated_at"])
	
	# 多言語データ
	if data.has("name"):
		unit.name = str(data["name"])
	if data.has("description"):
		unit.description = str(data["description"])
	
	return unit

# 文字列からUnitTypeに変換
static func _parse_unit_type(type_str: String) -> UnitType:
	match type_str:
		"Attack": return UnitType.ATTACK
		"Defense": return UnitType.DEFENSE
		"Support": return UnitType.SUPPORT
		_: return UnitType.ATTACK

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

# UnitTypeを文字列に変換
func get_type_string() -> String:
	match type:
		UnitType.ATTACK: return "Attack"
		UnitType.DEFENSE: return "Defense"
		UnitType.SUPPORT: return "Support"
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
		"created_at": created_at,
		"updated_at": updated_at,
		"name": name,
		"description": description
	}

# デバッグ用の文字列表現
func _to_string() -> String:
	return "MstUnit(id=%s, name=%s, rarity=%s)" % [id, name, get_rarity_string()]
