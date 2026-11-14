extends RefCounted

const ATLAS: JSON = preload("res://player/art/robot/robot_atlas.json")


static func slots() -> Array[String]:
	var result: Array[String] = []
	result.assign(ATLAS.data["draw_order"])
	return result


static func default_loadout() -> Dictionary[String, String]:
	var result: Dictionary[String, String] = {}
	result.assign(ATLAS.data["default_loadout"])
	return result


static func variants(slot: String) -> Dictionary:
	var modules: Dictionary = ATLAS.data["modules"]
	return modules.get(slot, {})


static func mount(id: String) -> Vector2:
	return point(ATLAS.data["mounts"][id])


static func point(coordinates: Dictionary) -> Vector2:
	return Vector2(float(coordinates["x"]), float(coordinates["y"]))
