extends Control

var _target: Control

@onready var _label: Label = $Label


func show_target(target: Control, message: String) -> void:
	_target = target
	_label.text = message
	_label.visible = not message.is_empty()
	show()
	_update_target()


func _process(_delta: float) -> void:
	if visible and is_instance_valid(_target):
		_update_target()


func _update_target() -> void:
	var transform_to_local: Transform2D = get_global_transform_with_canvas().affine_inverse() * _target.get_global_transform_with_canvas()
	var bounds := Rect2(transform_to_local * Vector2.ZERO, _target.size * transform_to_local.get_scale()).grow(3.0)
	_label.position = Vector2(
		clampf(bounds.get_center().x - _label.size.x * 0.5, 0.0, size.x - _label.size.x),
		maxf(0.0, bounds.position.y - _label.size.y - 4.0)
	).round()
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(_target):
		return
	var transform_to_local: Transform2D = get_global_transform_with_canvas().affine_inverse() * _target.get_global_transform_with_canvas()
	var bounds := Rect2(transform_to_local * Vector2.ZERO, _target.size * transform_to_local.get_scale()).grow(3.0)
	for corner in [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.ONE]:
		var point: Vector2 = bounds.position + corner * bounds.size
		var direction := Vector2(1.0 - 2.0 * corner.x, 1.0 - 2.0 * corner.y)
		draw_line(point, point + Vector2(direction.x * 6.0, 0.0), Color(0.85, 0.93, 0.9), 1.0)
		draw_line(point, point + Vector2(0.0, direction.y * 6.0), Color(0.85, 0.93, 0.9), 1.0)
