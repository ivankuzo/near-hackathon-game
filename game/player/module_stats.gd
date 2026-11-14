extends Resource

## Base health and movement speed before module bonuses.
@export var base_health: int = 100
@export var base_speed: int = 110
## Each module adds health (x) and movement speed in pixels per second (y).
@export var bonuses: Dictionary[String, Vector2i] = {}


func totals(loadout: Dictionary[String, String]) -> Vector2i:
	var result := Vector2i(base_health, base_speed)
	for id in loadout.values():
		if not bonuses.has(id):
			push_error("No stats configured for module '%s'." % id)
			return Vector2i.ZERO
		result += bonuses[id]
	return result
