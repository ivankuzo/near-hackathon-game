class_name PlayerBullet
extends CharacterBody2D

signal hit(collision: KinematicCollision2D, damage: int)

const Hurtbox = preload("res://combat/hurtbox/hurtbox.gd")

@export_range(1, 100, 1, "or_greater") var damage: int = 10
## Maximum shots per second while the fire button is held.
@export_range(0.1, 30.0, 0.1, "or_greater") var shots_per_second: float = 6.0
@export var shot_sound: AudioStream
@export_range(0.1, 2.0, 0.05) var shot_pitch_scale: float = 1.0
## Volume adjustment for this weapon's shot sound, in decibels.
@export var shot_volume_offset_db: float = 0.0
@export_group("Shot Shake")
## Maximum camera displacement in viewport pixels.
@export_range(0.0, 32.0, 0.1, "or_greater", "suffix:px") var shot_shake_amplitude: float = 1.8
@export_range(0.01, 2.0, 0.01, "or_greater", "suffix:s") var shot_shake_duration: float = 0.12
@export_range(1.0, 60.0, 1.0, "or_greater", "suffix:Hz") var shot_shake_frequency: float = 24.0
@export_group("")

## Travel speed in world pixels per second.
@export_range(1.0, 2000.0, 1.0, "or_greater") var speed: float = 420.0
## Maximum flight time in seconds. Impact animation finishes independently.
@export_range(0.1, 10.0, 0.1, "or_greater") var lifetime: float = 1.5

@export var light_color := Color(0.51, 0.71, 0.75)

## Play the projectile impact animation; damage and target effects are independent.
@export var impact_animation_enabled: bool = true

var _impacted: bool = false
var _light_energy: float

@onready var _sprite: AnimatedSprite2D = $Sprite2D
@onready var _light: PointLight2D = $GlowLight
@onready var _lifetime_timer: Timer = $LifetimeTimer


func _ready() -> void:
	_lifetime_timer.start(lifetime)
	_light.color = light_color
	_light_energy = _light.energy
	_sprite.animation_finished.connect(_on_animation_finished)
	_sprite.frame_changed.connect(_sync_light)
	_sprite.play(&"flight")


func _physics_process(delta: float) -> void:
	_move(global_transform.x.normalized() * speed * delta)


func _move(motion: Vector2) -> void:
	if is_queued_for_deletion():
		return
	var start: Vector2 = global_position
	var collision: KinematicCollision2D = move_and_collide(motion)
	if not start.is_equal_approx(global_position):
		var ray := PhysicsRayQueryParameters2D.create(start, global_position, Hurtbox.COLLISION_MASK)
		ray.collide_with_bodies = false
		ray.collide_with_areas = true
		ray.hit_from_inside = true
		var impact: Dictionary = get_world_2d().direct_space_state.intersect_ray(ray)
		var target := impact.get("collider") as Hurtbox
		if target != null and target.is_active():
			var point: Vector2 = impact["position"]
			var outward: Vector2 = impact["normal"]
			if outward.is_zero_approx():
				outward = -motion.normalized()
			_impact(point)
			target.receive_damage(damage, point, outward)
			return
	if collision != null:
		_impact(collision.get_position())
		hit.emit(collision, damage)


func _impact(world_point: Vector2) -> void:
	if _impacted:
		return
	_impacted = true
	global_position = world_point
	set_physics_process(false)
	_lifetime_timer.stop()
	set_deferred(&"collision_mask", 0)
	if not impact_animation_enabled:
		queue_free()
		return
	_sprite.play(&"impact")
	_sync_light()


func _sync_light() -> void:
	if _impacted:
		var progress: float = float(_sprite.frame) / 7.0
		_light.energy = _light_energy * 1.15 * (1.0 - progress)
	else:
		_light.energy = _light_energy * (1.0 + 0.12 * sin(float(_sprite.frame) * TAU / 6.0))


func _on_animation_finished() -> void:
	if _impacted:
		queue_free()
