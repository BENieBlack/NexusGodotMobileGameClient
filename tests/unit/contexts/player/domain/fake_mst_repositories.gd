## ホームの UseCase のテスト用の偽 mst Repository（行を差し替えられる）。
class_name FakeMstRepositories
extends RefCounted


class Level:
	extends MstPlayerLevelRepository
	## level → max_stamina
	var rows: Dictionary = {}

	func get_by_level(level: int) -> MstPlayerLevel:
		if not rows.has(level):
			return null
		var model := MstPlayerLevel.new()
		model.level = level
		model.max_stamina = rows[level]
		return model


class Config:
	extends MstConfigRepository
	## id → MstConfig
	var rows: Dictionary = {}

	func get_by_id(id: String) -> MstConfig:
		return rows.get(id, null)

	func put_int(id: String, value: String, value_type: String = "int") -> void:
		var model := MstConfig.new()
		model.id = id
		model.value = value
		model.value_type = value_type
		rows[id] = model


class FixedClock:
	extends Clock
	var now: int = 0

	func now_unix() -> int:
		return now
