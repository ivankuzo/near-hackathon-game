extends HBoxContainer

var _pulses: Dictionary[StringName, Tween] = {}
@onready var _counters: Dictionary[StringName, HBoxContainer] = {&"iron": $Iron, &"copper": $Copper, &"cobalt": $Cobalt}


func update_amount(kind: StringName, total: int, tint: Color) -> void:
	if not _counters.has(kind):
		push_error("No ore counter for '%s'." % kind)
		return
	var counter: HBoxContainer = _counters[kind]
	var value: Label = counter.get_node("Value")
	value.text = str(total)
	counter.modulate = tint
	if _pulses.has(kind):
		_pulses[kind].kill()
	counter.self_modulate = Color(1.7, 1.7, 1.7)
	var pulse: Tween = create_tween()
	pulse.tween_property(counter, ^"self_modulate", Color.WHITE, 0.20)
	_pulses[kind] = pulse
