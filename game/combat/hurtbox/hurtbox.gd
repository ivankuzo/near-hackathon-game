extends Area2D

signal damaged(amount: int, point: Vector2, outward: Vector2)

const COLLISION_MASK: int = 1 << 4

var _active: bool = true


func deactivate() -> void:
	_active = false
	set_deferred(&"collision_layer", 0)


func receive_damage(amount: int, point: Vector2, outward: Vector2) -> void:
	if _active:
		damaged.emit(amount, point, outward)


func is_active() -> bool:
	return _active
