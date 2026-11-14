extends Control

signal impact
signal finished

@onready var _label: Label = $Fail
@onready var _sound: AudioStreamPlayer = $ImpactSound
@onready var _low_sound: AudioStreamPlayer = $LowImpactSound


func show_failure() -> void:
	show()
	_label.pivot_offset = _label.size * 0.5
	_label.scale = Vector2.ONE * 1.7
	var animation: Tween = create_tween()
	animation.tween_property(_label, ^"scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	animation.tween_callback(_stamp)
	animation.tween_interval(1.4)
	animation.tween_callback(finished.emit)


func _stamp() -> void:
	_sound.play()
	_low_sound.play()
	impact.emit()
	var origin: Vector2 = _label.position
	var shake: Tween = create_tween()
	shake.tween_property(_label, ^"position", origin + Vector2(6, 2), 0.035)
	shake.tween_property(_label, ^"position", origin + Vector2(-4, -2), 0.04)
	shake.tween_property(_label, ^"position", origin + Vector2(2, 1), 0.04)
	shake.tween_property(_label, ^"position", origin, 0.05)
