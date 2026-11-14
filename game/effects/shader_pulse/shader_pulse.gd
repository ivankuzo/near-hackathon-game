extends Node

signal finished(target: CanvasItem)

## Uniform on the target-owned ShaderMaterial to animate back to zero.
@export var parameter: StringName
@export_range(0.0, 2.0, 0.01) var strength: float = 0.72
## Pulse duration in seconds.
@export_range(0.01, 0.5, 0.01) var duration: float = 0.16

var _active: Dictionary[CanvasItem, Tween] = {}


func play(target: CanvasItem) -> void:
	var material := target.material as ShaderMaterial
	if material == null:
		push_error("ShaderPulse requires a target-owned ShaderMaterial.")
		return
	if _active.has(target):
		_active[target].kill()
	else:
		target.tree_exiting.connect(_cancel.bind(target), CONNECT_ONE_SHOT)
	material.set_shader_parameter(parameter, strength)
	var tween := target.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var apply_strength := func(value: float) -> void:
		var current_material := target.material as ShaderMaterial
		current_material.set_shader_parameter(parameter, value)
	tween.tween_method(apply_strength, strength, 0.0, duration)
	_active[target] = tween
	tween.finished.connect(_finish.bind(target))


func _cancel(target: CanvasItem) -> void:
	_active[target].kill()
	_active.erase(target)


func _finish(target: CanvasItem) -> void:
	target.tree_exiting.disconnect(_cancel.bind(target))
	_active.erase(target)
	finished.emit(target)
