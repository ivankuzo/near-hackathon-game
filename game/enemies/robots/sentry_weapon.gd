extends Node2D

@export var projectile_scene: PackedScene
## Native left-facing gun mounts: idle followed by the eight running poses.
@export var mount_offsets: PackedVector2Array
@export_group("Aim")
## Maximum rotation to either side of the horizontal facing direction, in degrees.
@export_range(5.0, 70.0, 1.0, "suffix:degrees") var aim_half_angle: float = 35.0
@export_range(30.0, 720.0, 1.0, "suffix:degrees/s") var turn_speed: float = 190.0
@export_range(40.0, 500.0, 1.0, "suffix:px") var shooting_range: float = 235.0
@export var target_offset := Vector2(0, -24)
## Projectile collision geometry, rather than ground movement footprints.
@export_flags_2d_physics var obstacle_mask: int = 4
@export_group("Burst")
@export_range(0.1, 2.0, 0.05, "suffix:s") var charge_time: float = 0.65
@export_range(1, 8, 1) var burst_shots: int = 3
@export_range(0.05, 0.8, 0.01, "suffix:s") var shot_interval: float = 0.16
@export_range(0.2, 5.0, 0.05, "suffix:s") var cooldown: float = 1.6

var _disabled: bool = false
var _mirrored: bool = false
var _charge_left: float = 0.0
var _cooldown_left: float = 0.35
var _shot_left: float = 0.0
var _remaining: int = 0
var _recoil: float = 0.0
var _barrel_texture: AtlasTexture

@onready var _pivot: Node2D = $Pivot
@onready var _barrel: Sprite2D = $Pivot/Barrel
@onready var _muzzle: Marker2D = $Pivot/Muzzle
@onready var _charge: Sprite2D = $Pivot/Muzzle/Charge
@onready var _shots: Node2D = $Shots
@onready var _shot_sound: AudioStreamPlayer2D = $ShotSound


func _ready() -> void:
	assert(projectile_scene != null, "Sentry weapon needs a projectile scene.")
	assert(mount_offsets.size() == 9, "Sentry weapon needs a mount for idle and every running pose.")
	_barrel_texture = _barrel.texture.duplicate() as AtlasTexture
	_barrel.texture = _barrel_texture
	_charge.hide()


func set_pose(texture: Texture2D, mirrored: bool, world_center: Vector2) -> void:
	if _disabled:
		return
	var frame_texture := texture as AtlasTexture
	assert(frame_texture != null, "Sentry weapon requires atlas animation frames.")
	var row: int = roundi(frame_texture.region.position.y / frame_texture.region.size.y)
	var column: int = roundi(frame_texture.region.position.x / frame_texture.region.size.x)
	var tier: int = 0 if row == 0 else (1 if row == 2 else 2)
	_barrel_texture.region = Rect2(column * 16, tier * 8, 16, 8)
	_mirrored = mirrored
	var mount: Vector2 = mount_offsets[column]
	if mirrored:
		mount.x = -mount.x
	global_position = world_center + mount
	scale = Vector2(-1.0 if mirrored else 1.0, 1.0)


func is_in_sector(target: Vector2, margin: float = 0.0) -> bool:
	var facing: float = 1.0 if _mirrored else -1.0
	return (target.x - global_position.x) * facing >= 0.0 \
			and can_aim_from(global_position, target, margin)


func can_aim_from(origin: Vector2, target: Vector2, margin: float = 0.0) -> bool:
	var direction: Vector2 = target - origin
	var angle: float = atan2(absf(direction.y), absf(direction.x))
	return angle <= deg_to_rad(maxf(0.0, aim_half_angle - margin))


func _target_angle(target: Vector2) -> float:
	var direction: Vector2 = target - global_position
	if _mirrored:
		direction.x = -direction.x
	return wrapf(direction.angle() - PI, -PI, PI)


func has_clear_shot(target: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, _muzzle.global_position, obstacle_mask)
	query.hit_from_inside = true
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if not space.intersect_ray(query).is_empty():
		return false
	query.from = _muzzle.global_position
	query.to = target
	return space.intersect_ray(query).is_empty()


func update_aim(target: Vector2, delta: float, may_fire: bool) -> void:
	if _disabled:
		return
	var desired: float = _target_angle(target)
	_pivot.rotation = rotate_toward(_pivot.rotation,
			clampf(desired, -deg_to_rad(aim_half_angle), deg_to_rad(aim_half_angle)),
			deg_to_rad(turn_speed) * delta)
	_recoil = move_toward(_recoil, 0.0, delta * 18.0)
	_barrel.position.x = _recoil
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	var aligned: bool = absf(angle_difference(_pivot.rotation, desired)) < deg_to_rad(3.0)
	var in_range: bool = global_position.distance_squared_to(target) <= shooting_range * shooting_range
	if not may_fire or not in_range or not has_clear_shot(target):
		_cancel_burst()
		return
	if _cooldown_left > 0.0 or not is_in_sector(target):
		return
	if _charge_left <= 0.0 and _remaining == 0:
		_charge_left = charge_time
		_charge.show()
	if _charge_left > 0.0:
		_charge_left = maxf(0.0, _charge_left - delta)
		var progress: float = 1.0 - _charge_left / charge_time
		_charge.scale = Vector2.ONE * lerpf(0.35, 1.0, progress)
		_charge.modulate.a = progress * (0.8 + 0.2 * sin(progress * 35.0))
		if _charge_left > 0.0:
			return
		_remaining = burst_shots
		_shot_left = 0.0
	# Finish charging while tracking, but only release shots along the target direction.
	if not aligned:
		return
	_shot_left -= delta
	if _remaining > 0 and _shot_left <= 0.0:
		_fire()
		_remaining -= 1
		_shot_left = shot_interval
		if _remaining == 0:
			_cooldown_left = cooldown
			_charge.hide()


func _fire() -> void:
	var projectile := projectile_scene.instantiate() as Node2D
	assert(projectile != null, "Sentry projectile must be a Node2D scene.")
	_shots.add_child(projectile)
	var direction: Vector2 = -_pivot.global_transform.x.normalized()
	projectile.global_transform = Transform2D(direction.angle(), _muzzle.global_position)
	_shot_sound.play()
	_recoil = 2.0


func _cancel_burst() -> void:
	if _charge_left > 0.0 or _remaining > 0:
		_cooldown_left = maxf(_cooldown_left, 0.25)
	_charge_left = 0.0
	_remaining = 0
	_charge.hide()


func disable() -> void:
	_disabled = true
	_cancel_burst()
	_pivot.hide()
