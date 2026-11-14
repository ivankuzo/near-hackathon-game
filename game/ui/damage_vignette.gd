extends ColorRect

var _fade: Tween


func flash() -> void:
	if _fade != null:
		_fade.kill()
	modulate.a = 1.0
	_fade = create_tween()
	_fade.tween_property(self, ^"modulate:a", 0.0, 0.35)
