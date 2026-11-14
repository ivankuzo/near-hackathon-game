extends Control

@export var font: Font


func _draw() -> void:
	if font == null:
		push_error("Onboarding controls require a font.")
		return
	_draw_key(Rect2(40, 0, 36, 36), "W")
	_draw_key(Rect2(0, 40, 36, 36), "A")
	_draw_key(Rect2(40, 40, 36, 36), "S")
	_draw_key(Rect2(80, 40, 36, 36), "D")
	_draw_key(Rect2(158, 40, 76, 36), "LMB")
	_draw_caption(Rect2(0, 84, 116, 20), "MOVE")
	_draw_caption(Rect2(158, 84, 76, 20), "SHOOT")


func _draw_key(rect: Rect2, text: String) -> void:
	draw_rect(rect, Color.BLACK)
	var baseline: float = rect.position.y + (rect.size.y - font.get_height(32)) * 0.5 + font.get_ascent(32) + 4.0
	draw_string(font, Vector2(rect.position.x, baseline).round(), text,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 32, Color.WHITE)


func _draw_caption(rect: Rect2, text: String) -> void:
	var baseline: float = rect.position.y + (rect.size.y - font.get_height(16)) * 0.5 + font.get_ascent(16)
	draw_string(font, Vector2(rect.position.x, baseline).round(), text,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 16, Color(0.67, 0.72, 0.7))
