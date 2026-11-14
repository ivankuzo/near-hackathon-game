extends Node2D

const Hurtbox = preload("res://combat/hurtbox/hurtbox.gd")

@export_range(20.0, 800.0, 1.0, "suffix:px/s") var speed: float = 210.0
@export_range(0.1, 5.0, 0.1, "suffix:s") var lifetime: float = 2.5
@export_range(1, 100, 1) var damage: int = 12
## Projectile terrain and the player's receiving area; never enemy hurtboxes.
@export_flags_2d_physics var collision_mask: int = 36
@export_range(2, 16, 1) var trail_points: int = 7
## Assigned by the projectile scene, independent of the light node's name.
@export var light: PointLight2D

var _age: float = 0.0
## Play the projectile impact animation; damage and target effects are independent.
@export var impact_animation_enabled: bool = true

var _impacted: bool = false
var _positions := PackedVector2Array()
var _light_energy: float = 0.0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _trail: Line2D = $Trail
@onready var _halo: Sprite2D = $Halo


func _ready() -> void:
	if light == null:
		push_error("SentryBolt requires a PointLight2D assigned to Light in the Inspector.")
		set_physics_process(false)
		queue_free()
		return
	_light_energy = light.energy
	_trail.global_transform = Transform2D.IDENTITY
	_sprite.frame_changed.connect(_sync_light)
	_sprite.play(&"flight")
	_sync_light()
	_sprite.animation_finished.connect(_on_animation_finished)


func _physics_process(delta: float) -> void:
	_age += delta
	if _impacted:
		_trail.modulate.a = maxf(0.0, _trail.modulate.a - delta * 12.0)
		_halo.modulate.a = maxf(0.0, _halo.modulate.a - delta * 10.0)
		return
	if _age >= lifetime:
		queue_free()
		return
	var destination: Vector2 = global_position + global_transform.x.normalized() * speed * delta
	var query := PhysicsRayQueryParameters2D.create(global_position, destination, collision_mask)
	query.collide_with_areas = true
	query.hit_from_inside = true
	var contact: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if contact.is_empty():
		global_position = destination
	else:
		global_position = contact["position"]
		_impacted = true
		if impact_animation_enabled:
			_sprite.play(&"impact")
			_sync_light()
		var receiver := contact["collider"] as Hurtbox
		if receiver != null:
			var outward: Vector2 = contact["normal"]
			if outward.is_zero_approx():
				outward = -global_transform.x.normalized()
			receiver.receive_damage(damage, global_position, outward)
		if not impact_animation_enabled:
			queue_free()
			return
	_positions.append(global_position)
	if _positions.size() > trail_points:
		_positions.remove_at(0)
	_trail.points = _positions


func _sync_light() -> void:
	if _impacted:
		var last_frame: int = _sprite.sprite_frames.get_frame_count(&"impact") - 1
		var progress: float = float(_sprite.frame) / maxf(1.0, float(last_frame))
		light.energy = _light_energy * 1.15 * (1.0 - progress)
		return
	var phase: float = TAU * float(_sprite.frame) / _sprite.sprite_frames.get_frame_count(&"flight")
	light.energy = _light_energy * (1.0 + 0.18 * sin(phase))
	_halo.self_modulate.a = 0.8 + 0.2 * cos(phase)


func _on_animation_finished() -> void:
	if _impacted:
		queue_free()
