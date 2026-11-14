extends CanvasLayer

var _background: ColorRect
var _owns_pause: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_background = ColorRect.new()
	_background.color = Color(0.03, 0.04, 0.05)
	add_child(_background)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var label := Label.new()
	label.text = "ROTATE YOUR PHONE"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override(&"font", preload("res://ui/fonts/m6x11.tres"))
	label.add_theme_font_size_override(&"font_size", 32)
	_background.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	var window_size: Vector2i = DisplayServer.window_get_size()
	var portrait: bool = window_size.y > window_size.x
	_background.visible = portrait
	if portrait and not get_tree().paused:
		get_tree().paused = true
		_owns_pause = true
	elif not portrait and _owns_pause:
		get_tree().paused = false
		_owns_pause = false


func _exit_tree() -> void:
	if _owns_pause:
		get_tree().paused = false
