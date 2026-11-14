extends Node2D

signal collected(kind: StringName, tint: Color, world_point: Vector2)

@export var ore_type: StringName = &"iron"

@export var light: PointLight2D
@export var glow_color := Color(0.78, 0.90, 1.0)
@export_range(0.0, 1.0, 0.01) var glow_strength: float = 0.38
@export_group("Landing")
@export_range(0.1, 1.5, 0.01, "suffix:s") var flight_time: float = 0.48
@export_range(0.0, 100.0, 1.0, "suffix:px") var initial_height: float = 30.0
@export_range(0.0, 80.0, 1.0, "suffix:px") var toss_height: float = 22.0

var _origin: Vector2
var _landing: Vector2
var _elapsed: float = 0.0
var _launch_angle: float = 0.0
var _rest_angle: float = 0.0
var _surface_material: ShaderMaterial
var _settle: Tween
var _available: bool = false
var _collecting: bool = false
var _collector: Node2D
var _pickup_origin: Vector2
var _pickup_offset: Vector2
var _pickup_duration: float
var _base_energy: float
var _trail_points := PackedVector2Array()

@onready var _pickup_area: Area2D = $PickupArea
@onready var _trail: Line2D = $PickupTrail
@onready var _visual: Node2D = $Visual
@onready var _surface: Sprite2D = $Visual/Sprite
@onready var _emission: Sprite2D = $Visual/Emission
@onready var _halo: Sprite2D = $Visual/Halo
@onready var _shadow: Sprite2D = $Shadow
@onready var _shadow_scale: Vector2 = _shadow.scale
@onready var _visibility: VisibleOnScreenNotifier2D = $Visibility


func _ready() -> void:
	set_process(false)
	if light == null:
		push_error("Ore shard requires its GlowLight assigned in the Inspector.")
		queue_free()
		return
	_surface_material = _surface.material.duplicate() as ShaderMaterial
	_surface.material = _surface_material
	_base_energy = light.energy
	_trail.global_transform = Transform2D.IDENTITY
	light.color = glow_color
	_emission.self_modulate = Color(glow_color.r, glow_color.g, glow_color.b, glow_strength)
	_halo.self_modulate = Color(glow_color.r, glow_color.g, glow_color.b, _halo.self_modulate.a)
	_visibility.screen_entered.connect(_on_screen_entered)
	_visibility.screen_exited.connect(_on_screen_exited)
	light.enabled = _visibility.is_on_screen()


func launch(world_origin: Vector2, landing: Vector2) -> void:
	_origin = world_origin
	_landing = landing
	_elapsed = 0.0
	_rest_angle = randf_range(-0.18, 0.18)
	_launch_angle = _rest_angle + randf_range(-0.75, 0.75)
	global_position = world_origin
	_visual.position.y = -initial_height
	_visual.rotation = _launch_angle
	_shadow.scale = _shadow_scale * 0.6
	_shadow.modulate.a = 0.35
	_update_shadow_anchor()
	set_process(true)


func _process(delta: float) -> void:
	if _collecting:
		_update_collection(delta)
		return
	_elapsed += delta
	var progress: float = clampf(_elapsed / flight_time, 0.0, 1.0)
	global_position = _origin.lerp(_landing, 1.0 - pow(1.0 - progress, 2.0))
	_visual.position.y = -(initial_height * (1.0 - progress)
			+ 4.0 * toss_height * progress * (1.0 - progress))
	_visual.rotation = lerp_angle(_launch_angle, _rest_angle, progress)
	_update_shadow_anchor()
	_shadow.scale = _shadow_scale * lerpf(0.6, 1.0, progress)
	_shadow.modulate.a = lerpf(0.35, 1.0, progress)
	if progress >= 1.0:
		set_process(false)
		_settle = create_tween()
		_settle.tween_method(_set_visual_height, 0.0, -3.0, 0.06).set_trans(Tween.TRANS_SINE)
		_settle.tween_method(_set_visual_height, -3.0, 0.0, 0.10).set_trans(Tween.TRANS_QUAD)
		_settle.finished.connect(_make_available, CONNECT_ONE_SHOT)


func _make_available() -> void:
	_available = true
	_pickup_area.set_deferred(&"collision_layer", 64)


func can_collect() -> bool:
	return _available and not _collecting


func collect(target: Node2D, offset: Vector2, duration: float) -> bool:
	if not can_collect() or not is_instance_valid(target):
		return false
	_available = false
	_collecting = true
	_collector = target
	_pickup_origin = global_position
	_pickup_offset = offset
	_pickup_duration = maxf(duration, 0.1)
	_elapsed = 0.0
	_pickup_area.set_deferred(&"collision_layer", 0)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(glow_color, 0.0), Color(glow_color, 0.8)])
	_trail.gradient = gradient
	_trail.show()
	light.energy = _base_energy * 1.25
	set_process(true)
	return true


func _update_collection(delta: float) -> void:
	if not is_instance_valid(_collector):
		_collecting = false
		global_position = _pickup_origin
		_visual.position = Vector2.ZERO
		_visual.scale = Vector2.ONE
		_visual.modulate = Color.WHITE
		_shadow.modulate.a = 1.0
		light.energy = _base_energy
		_trail.hide()
		_trail_points.clear()
		_trail.clear_points()
		_update_shadow_anchor()
		_make_available()
		set_process(false)
		return
	_elapsed += delta
	var t: float = clampf(_elapsed / _pickup_duration, 0.0, 1.0)
	var flight: float = clampf((t - 0.18) / 0.82, 0.0, 1.0)
	var travel: float = flight * flight
	var destination: Vector2 = _collector.global_position
	var bend: Vector2 = (destination - _pickup_origin).normalized().orthogonal() * 8.0
	global_position = _pickup_origin.lerp(destination, travel) + bend * sin(PI * travel)
	_visual.position = _pickup_offset * travel + Vector2(0, 16.0 * travel
			- 7.0 * sin(PI * t) - 5.0 * sin(PI * flight))
	_visual.scale = Vector2.ONE * lerpf(1.0, 0.10, smoothstep(0.3, 1.0, t))
	_visual.modulate.a = 1.0 - smoothstep(0.82, 1.0, t)
	_shadow.modulate.a = 1.0 - smoothstep(0.0, 0.25, t)
	light.energy = _base_energy * 1.25 * (1.0 - smoothstep(0.6, 1.0, t))
	_update_shadow_anchor()
	_trail_points.append(_surface.global_position)
	if _trail_points.size() > 7:
		_trail_points.remove_at(0)
	_trail.points = _trail_points
	_trail.modulate.a = 1.0 - smoothstep(0.75, 1.0, t)
	if t >= 1.0:
		_collecting = false
		collected.emit(ore_type, glow_color, destination + _pickup_offset)
		queue_free()


func _set_visual_height(value: float) -> void:
	_visual.position.y = value
	_update_shadow_anchor()


func _update_shadow_anchor() -> void:
	_surface_material.set_shader_parameter(&"ground_anchor", _surface.to_local(global_position))


func _on_screen_entered() -> void:
	light.enabled = true


func _on_screen_exited() -> void:
	light.enabled = false
