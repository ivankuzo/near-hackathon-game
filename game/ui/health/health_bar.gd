extends Control

const BAR_WIDTH_PER_HEALTH: float = 1.6
const BAR_HEIGHT: int = 8
const BAR_X: int = 36
const BAR_Y: int = 7

var _current: int = 0
var _maximum: int = 0
var _fill: float = 1.0
var _trail: float = 1.0
var _flash: float = 0.0
var _damage_tween: Tween

func set_health(current: int, maximum: int) -> void:
	if maximum <= 0:
		push_error("Health bar requires positive maximum health.")
		return
	var next_fill: float = clampf(float(current) / float(maximum), 0.0, 1.0)
	var first_update: bool = _maximum == 0
	var took_damage: bool = not first_update and current < _current
	_current = current
	_maximum = maximum
	_fill = next_fill
	custom_minimum_size.x = BAR_X + roundi(float(maximum) * BAR_WIDTH_PER_HEALTH)
	if _damage_tween != null:
		_damage_tween.kill()
	if took_damage:
		_trail = maxf(_trail, _fill)
		_flash = 1.0
		_damage_tween = create_tween()
		_damage_tween.tween_method(_set_flash, 1.0, 0.0, 0.18)
		_damage_tween.tween_interval(0.15)
		_damage_tween.tween_method(_set_trail, _trail, _fill, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_trail = _fill
		_flash = 0.0
	queue_redraw()


func _set_flash(value: float) -> void:
	_flash = value
	queue_redraw()


func _set_trail(value: float) -> void:
	_trail = value
	queue_redraw()


func _draw() -> void:
	# All geometry uses whole pixels; animated widths are snapped to the same grid.
	var bar_width: int = roundi(float(_maximum) * BAR_WIDTH_PER_HEALTH)
	draw_rect(Rect2(BAR_X, BAR_Y, bar_width, BAR_HEIGHT), Color("511c32"))
	var trail_width: int = roundi(float(bar_width) * _trail)
	var fill_width: int = roundi(float(bar_width) * _fill)
	if trail_width > 0:
		draw_rect(Rect2(BAR_X, BAR_Y, trail_width, BAR_HEIGHT), Color("ffd1a8"))
	if fill_width > 0:
		var fill_color := Color("c64a53") if _fill > 0.25 else Color("a73540")
		fill_color = fill_color.lerp(Color("fff1dc"), _flash * 0.65)
		draw_rect(Rect2(BAR_X, BAR_Y, fill_width, BAR_HEIGHT), fill_color)
		draw_rect(Rect2(BAR_X, BAR_Y, fill_width, 1), fill_color.lightened(0.35))
		draw_rect(Rect2(BAR_X, BAR_Y + BAR_HEIGHT - 1, fill_width, 1), fill_color.darkened(0.3))
