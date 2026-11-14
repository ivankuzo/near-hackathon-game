class_name MobileControls
extends Control

const RADIUS: float = 65.0
const DEADZONE: float = 0.18
const FIRE_THRESHOLD: float = 0.75

var move_vector: Vector2 = Vector2.ZERO
var aim_vector: Vector2 = Vector2.ZERO
var firing: bool = false
var _move_touch: int = -1
var _aim_touch: int = -1
var _move_center: Vector2
var _aim_center: Vector2


static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < size.x * 0.5 and _move_touch == -1:
				_move_touch = event.index
				_move_center = event.position
			elif event.position.x >= size.x * 0.5 and _aim_touch == -1:
				_aim_touch = event.index
				_aim_center = event.position
		else:
			if event.index == _move_touch:
				_move_touch = -1
				move_vector = Vector2.ZERO
			if event.index == _aim_touch:
				_aim_touch = -1
				aim_vector = Vector2.ZERO
				firing = false
		queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == _move_touch:
			move_vector = _stick_vector(event.position - _move_center)
		elif event.index == _aim_touch:
			aim_vector = _stick_vector(event.position - _aim_center)
			firing = aim_vector.length() >= FIRE_THRESHOLD
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_PAUSED:
		_move_touch = -1
		_aim_touch = -1
		move_vector = Vector2.ZERO
		aim_vector = Vector2.ZERO
		firing = false
		queue_redraw()


func _stick_vector(offset: Vector2) -> Vector2:
	var value: Vector2 = (offset / RADIUS).limit_length(1.0)
	return Vector2.ZERO if value.length() < DEADZONE else value


func _draw() -> void:
	var left_center: Vector2 = _move_center if _move_touch != -1 else Vector2(120.0, size.y - 120.0)
	var right_center: Vector2 = _aim_center if _aim_touch != -1 else Vector2(size.x - 120.0, size.y - 120.0)
	_draw_stick(left_center, move_vector)
	_draw_stick(right_center, aim_vector)


func _draw_stick(center: Vector2, value: Vector2) -> void:
	draw_circle(center, RADIUS, Color(0.05, 0.07, 0.08, 0.55))
	draw_arc(center, RADIUS, 0.0, TAU, 32, Color(0.85, 0.9, 0.88, 0.45), 2.0)
	draw_circle(center + value * RADIUS, 22.0, Color(0.85, 0.9, 0.88, 0.7))
