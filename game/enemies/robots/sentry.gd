extends "res://enemies/robots/robot_chaser.gd"

const SentryWeapon = preload("res://enemies/robots/sentry_weapon.gd")

@export_group("Ranged Movement")
## Distance to reach before settling into a firing position; shooting range is the outer limit.
@export_range(40.0, 300.0, 1.0, "suffix:px") var preferred_distance: float = 155.0
## Aim farther inside the gun sector before settling, preventing movement at its boundary.
@export_range(1.0, 25.0, 1.0, "suffix:degrees") var aim_margin: float = 8.0
## Speed while finding a firing position near the player; Move Speed controls pursuit.
@export_range(1.0, 300.0, 1.0, "suffix:px/s") var reposition_speed: float = 86.0

var _position_in: float = 0.0
var _firing_goal: Vector2
var _holding_position: bool = false

@onready var _weapon: SentryWeapon = $Visual/Weapon


func _ready() -> void:
	super._ready()
	assert(preferred_distance < _weapon.shooting_range,
			"Sentry Preferred Distance must be smaller than Weapon Shooting Range.")
	assert(aim_margin < _weapon.aim_half_angle,
			"Sentry Aim Margin must be smaller than Weapon Aim Half Angle.")
	visuals.hurtbox_pose_changed.connect(_weapon.set_pose)
	visuals.publish_hurtbox_pose()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_instance_valid(_player) or is_defeated():
		return
	var target: Vector2 = _weapon.global_position - _weapon.global_transform.x * 100.0
	if _state == State.CHASE:
		# Movement animations face the travel direction; keep the gun facing the target.
		visuals.face_toward(_player.global_position)
		target = _player.global_position + _weapon.target_offset
	elif _state == State.SEARCH:
		target = _last_seen + _weapon.target_offset
	_weapon.update_aim(target, delta, _state == State.CHASE)


func _enter(state: State) -> void:
	if state != _state:
		_holding_position = false
		_position_in = 0.0
	super._enter(state)


func _chase(delta: float) -> void:
	var player_position: Vector2 = _player.global_position
	visuals.face_toward(player_position)
	var target: Vector2 = player_position + _weapon.target_offset
	var gun_distance: float = _weapon.global_position.distance_to(target)
	var clear_shot: bool = _weapon.has_clear_shot(target)
	var maximum_distance: float = _weapon.shooting_range if _holding_position else preferred_distance
	var sector_margin: float = 0.0 if _holding_position else aim_margin
	if gun_distance <= maximum_distance \
			and _weapon.is_in_sector(target, sector_margin) and clear_shot:
		_holding_position = true
		_position_in = 0.0
		_stop()
		return

	_holding_position = false
	if not _weapon.is_in_sector(target, aim_margin) or not clear_shot:
		_reposition(player_position, delta)
	else:
		_move_toward(_last_seen, move_speed, 0.0, delta)


func _reposition(player_position: Vector2, delta: float) -> void:
	_position_in -= delta
	if _position_in <= 0.0:
		_position_in = 0.45
		_firing_goal = _last_seen
		var best_distance: float = INF
		var current_side: float = -1.0 if global_position.x < player_position.x else 1.0
		for side: float in [current_side, -current_side]:
			for height: float in [0.0, 0.4, -0.4]:
				var candidate: Vector2 = player_position + Vector2(side, height) * preferred_distance
				var gun_mount: Vector2 = _weapon.global_position - global_position
				gun_mount.x = -side * absf(gun_mount.x)
				if not _weapon.can_aim_from(candidate + gun_mount,
						player_position + _weapon.target_offset, aim_margin):
					continue
				var distance: float = global_position.distance_squared_to(candidate)
				if distance >= best_distance:
					continue
				var query := PhysicsRayQueryParameters2D.create(candidate, player_position, sight_obstacle_mask)
				query.hit_from_inside = true
				if not get_world_2d().direct_space_state.intersect_ray(query).is_empty():
					continue
				if _is_route_blocked(global_transform, candidate - global_position):
					var route: PackedVector2Array = _find_route.call(global_position, candidate)
					if route.is_empty():
						continue
					var end_transform: Transform2D = global_transform
					end_transform.origin = route[-1]
					if _is_route_blocked(end_transform, candidate - route[-1]):
						continue
				best_distance = distance
				_firing_goal = candidate
		_repath_in = 0.0
	_move_toward(_firing_goal, reposition_speed, ARRIVAL_DISTANCE, delta)


func _take_damage(amount: int, point: Vector2, outward: Vector2) -> void:
	super._take_damage(amount, point, outward)
	if is_defeated():
		_weapon.disable()
