extends CanvasLayer

var _mouse_inside: bool = false
var _window_focused: bool = false

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _window: Window = get_window()
@onready var _viewport: Viewport = get_viewport()


func _ready() -> void:
	_window.mouse_entered.connect(_on_mouse_entered)
	_window.mouse_exited.connect(_on_mouse_exited)
	_window.focus_entered.connect(_on_focus_entered)
	_window.focus_exited.connect(_on_focus_exited)
	_window_focused = _window.has_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_inside = _viewport.get_visible_rect().has_point(event.position)


func _process(_delta: float) -> void:
	var mouse_position: Vector2 = _viewport.get_mouse_position()
	_sprite.position = mouse_position
	_set_active(
		_mouse_inside
		and _window_focused
		and _viewport.get_visible_rect().has_point(mouse_position)
	)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _set_active(active: bool) -> void:
	if _sprite.visible == active:
		return
	_sprite.visible = active
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if active else Input.MOUSE_MODE_VISIBLE


func _on_mouse_entered() -> void:
	_mouse_inside = true


func _on_mouse_exited() -> void:
	_mouse_inside = false
	_set_active(false)


func _on_focus_entered() -> void:
	_window_focused = true


func _on_focus_exited() -> void:
	_window_focused = false
	_set_active(false)
