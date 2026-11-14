extends CharacterBody2D

signal defeated

const AnimatedHurtbox = preload("res://combat/hurtbox/animated_hurtbox.gd")
const RobotVisuals = preload("res://enemies/robots/robot_enemy_visual.gd")
const MeleeAttack = preload("res://enemies/robots/melee_attack.gd")
const SENSE_INTERVAL: float = 0.16
const REPATH_INTERVAL: float = 0.24
const ARRIVAL_DISTANCE: float = 5.0
const WAYPOINT_TOLERANCE: float = 2.0

enum State { DORMANT, WAKING, PATROL, CHASE, SEARCH }

@export_group("Health")
@export_range(1, 1000, 1, "or_greater") var max_health: int = 30

@export_group("Movement")
## Pursuit speed in world pixels per second.
@export_range(1.0, 300.0, 1.0) var move_speed: float = 100.0
@export_range(1.0, 120.0, 1.0) var stop_distance: float = 42.0
## Optional melee attack, configured on close-range enemy scenes.
@export var melee_attack: MeleeAttack
## Static obstacles used for route checks; exclude other characters.
@export_flags_2d_physics var route_obstacle_mask: int = 1

@export_group("Patrol")
@export_range(1.0, 150.0, 1.0) var patrol_speed: float = 32.0
## Radius around the current patrol area.
@export_range(0.0, 500.0, 1.0) var patrol_radius: float = 95.0
## Pause between patrol moves in seconds, from minimum to maximum.
@export var patrol_pause := Vector2(0.6, 1.6)

@export_group("Detection")
@export_range(1.0, 600.0, 1.0) var sight_radius: float = 180.0
## Distance from the player required to give up after searching.
@export_range(1.0, 1200.0, 1.0) var disengage_radius: float = 360.0
## Seconds to search after reaching the last seen position while the player is far away.
@export_range(0.1, 10.0, 0.1) var search_time: float = 3.2
@export_flags_2d_physics var sight_obstacle_mask: int = 1

@export_group("Wake")
@export_range(1.0, 500.0, 1.0) var wake_radius: float = 110.0
@export_range(0.1, 3.0, 0.05) var wake_duration: float = 0.55

var current_health: int

var _player: Node2D
var _find_route: Callable
var _patrol_center: Vector2
var _search_arrived: bool = false
var _search_left: float = 0.0
var _alerted: bool = false
var _state: State = State.PATROL
var _state_left: float = 0.0
var _sense_in: float = 0.0
var _last_seen: Vector2
var _patrol_goal: Vector2
var _patrol_moving: bool = false
var _random := RandomNumberGenerator.new()
var _repath_in: float = 0.0
var _direct: bool = false
var _waypoints := PackedVector2Array()
var _waypoint: int = 0
var _route_query := PhysicsShapeQueryParameters2D.new()

@onready var _footprint: CollisionShape2D = $Footprint
@onready var _hurtbox: AnimatedHurtbox = $Hurtbox
@onready var _activation_sound: AudioStreamPlayer2D = $ActivationSound
@onready var visuals: RobotVisuals = $Visual


func _ready() -> void:
	set_physics_process(false)
	current_health = max_health
	if not visuals.is_configured():
		_hurtbox.deactivate()
		return
	_hurtbox.damaged.connect(_take_damage)
	visuals.hurtbox_pose_changed.connect(_hurtbox.set_pose)
	visuals.publish_hurtbox_pose()


func _take_damage(amount: int, point: Vector2, outward: Vector2) -> void:
	if is_defeated() or amount <= 0:
		return
	current_health = maxi(0, current_health - amount)
	visuals.play_hit(point, outward, current_health, max_health)
	if is_defeated():
		defeated.emit()
		if melee_attack != null:
			melee_attack.stop()
		set_physics_process(false)
		_activation_sound.stop()
		velocity = Vector2.ZERO
		_footprint.set_deferred(&"disabled", true)
		_hurtbox.deactivate()
		await visuals.play_death()
		queue_free()
	elif is_instance_valid(_player):
		_last_seen = _player.global_position
		_alerted = true
		if _state == State.DORMANT:
			_enter(State.WAKING)
		elif _state != State.WAKING:
			_enter(State.CHASE)



func is_defeated() -> bool:
	return current_health == 0


func activate(
	player: Node2D, find_route: Callable, starts_asleep: bool, seed_value: int,
	saved_health: int = -1
) -> bool:
	if not _hurtbox.is_active() or not is_instance_valid(player) or not find_route.is_valid():
		push_error("Enemy requires configured visuals, a player and a route finder.")
		return false
	if melee_attack != null and not player is Player:
		push_error("Melee enemy requires a Player target.")
		return false
	_player = player
	_find_route = find_route
	_patrol_center = global_position
	if saved_health > 0:
		current_health = mini(saved_health, max_health)
	visuals.set_health(current_health, max_health)
	_random.seed = seed_value
	_sense_in = _random.randf_range(0.0, SENSE_INTERVAL)
	_enter(State.DORMANT if starts_asleep else State.PATROL)
	set_physics_process(true)
	return true


func is_dormant() -> bool:
	return _state == State.DORMANT


func wake_up() -> void:
	if is_dormant() and not is_defeated():
		_enter(State.WAKING)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		_stop()
		set_physics_process(false)
		return

	var player_position: Vector2 = _player.global_position
	_state_left = maxf(0.0, _state_left - delta)
	if _state == State.DORMANT:
		_sense_in -= delta
		if _sense_in <= 0.0:
			_sense_in = SENSE_INTERVAL
			if _can_see(player_position, wake_radius):
				_enter(State.WAKING)
		return
	if _state == State.WAKING:
		if _state_left > 0.0:
			return
		_enter(State.CHASE if _alerted else State.PATROL)
		_sense_in = 0.0

	_sense_in -= delta
	if _sense_in <= 0.0:
		_sense_in = SENSE_INTERVAL
		_update_detection(player_position)

	match _state:
		State.PATROL:
			_patrol(delta)
		State.CHASE:
			_chase(delta)
		State.SEARCH:
			_search(player_position, delta)


func _chase(delta: float) -> void:
	_move_toward(_last_seen, move_speed, stop_distance, delta)
	if melee_attack != null:
		var target := _player as Player
		if target != null:
			melee_attack.update_attack(self, target, delta)


func _search(player_position: Vector2, delta: float) -> void:
	if not _search_arrived:
		_move_toward(_last_seen, move_speed, 0.0, delta)
		var route_finished: bool = not _direct and _waypoint >= _waypoints.size()
		if global_position.distance_to(_last_seen) <= ARRIVAL_DISTANCE or route_finished:
			_search_arrived = true
			_patrol_center = global_position
			_patrol_moving = false
			_pause_patrol()
		return

	var escape_radius: float = maxf(disengage_radius, sight_radius)
	if global_position.distance_squared_to(player_position) > escape_radius * escape_radius:
		_search_left = maxf(0.0, _search_left - delta)
	else:
		_search_left = search_time
	if _search_left <= 0.0:
		_enter(State.PATROL)
	else:
		_patrol(delta)


func _update_detection(player_position: Vector2) -> void:
	var detection_radius: float = sight_radius
	if _state == State.CHASE or _state == State.SEARCH:
		detection_radius = maxf(disengage_radius, sight_radius)
	if _can_see(player_position, detection_radius):
		_last_seen = player_position
		if _state != State.CHASE:
			_enter(State.CHASE)
	elif _state == State.CHASE:
		_enter(State.SEARCH)


func _can_see(player_position: Vector2, detection_radius: float) -> bool:
	if global_position.distance_squared_to(player_position) > detection_radius * detection_radius:
		return false
	if global_position.is_equal_approx(player_position):
		return true
	var ray := PhysicsRayQueryParameters2D.create(global_position, player_position, sight_obstacle_mask)
	ray.hit_from_inside = true
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


func _enter(state: State) -> void:
	var previous_state: State = _state
	_state = state
	_repath_in = 0.0
	_stop()
	match state:
		State.DORMANT:
			visuals.set_awake(false)
		State.WAKING:
			_state_left = wake_duration
			visuals.play_wake(wake_duration)
			_activation_sound.play()
		State.PATROL:
			visuals.set_awake(true)
			_patrol_moving = false
			_pause_patrol()
		State.CHASE:
			if previous_state != State.CHASE and not _activation_sound.playing:
				_activation_sound.play()
			_alerted = true
			visuals.set_awake(true)
		State.SEARCH:
			_search_arrived = false
			_search_left = search_time


func _patrol(delta: float) -> void:
	if _patrol_moving:
		if global_position.distance_to(_patrol_goal) <= ARRIVAL_DISTANCE:
			_patrol_moving = false
			_pause_patrol()
		else:
			_move_toward(_patrol_goal, patrol_speed, 0.0, delta)
		return
	if _state_left > 0.0 or is_zero_approx(patrol_radius):
		return
	for _attempt in range(5):
		var direction := Vector2.from_angle(_random.randf_range(0.0, TAU))
		var point: Vector2 = _patrol_center + direction * _random.randf_range(patrol_radius * 0.35, patrol_radius)
		if point.distance_to(global_position) > ARRIVAL_DISTANCE and not _is_route_blocked(
			global_transform, point - global_position
		):
			_patrol_goal = point
			_patrol_moving = true
			_repath_in = 0.0
			return
	_pause_patrol()


func _pause_patrol() -> void:
	_stop()
	_state_left = _random.randf_range(minf(patrol_pause.x, patrol_pause.y), maxf(patrol_pause.x, patrol_pause.y))


func _move_toward(destination: Vector2, speed: float, stop: float, delta: float) -> void:
	_repath_in -= delta
	if _repath_in <= 0.0:
		_plan_route(destination)
		_repath_in = REPATH_INTERVAL

	var motion: Vector2 = Vector2.ZERO
	if _direct:
		var distance: Vector2 = destination - global_position
		motion = distance.normalized() * maxf(0.0, distance.length() - stop)
	else:
		while _waypoint < _waypoints.size():
			motion = _waypoints[_waypoint] - global_position
			if motion.length_squared() > WAYPOINT_TOLERANCE * WAYPOINT_TOLERANCE:
				break
			motion = Vector2.ZERO
			_waypoint += 1
	velocity = motion.limit_length(speed * delta) / delta
	move_and_slide()
	visuals.set_motion(get_real_velocity())


func _plan_route(destination: Vector2) -> void:
	_direct = not _is_route_blocked(global_transform, destination - global_position)
	if _direct:
		return
	_waypoints = _find_route.call(global_position, destination)
	_waypoint = 0
	if _waypoints.size() > 1 and not _is_route_blocked(global_transform, _waypoints[1] - global_position):
		_waypoint = 1


func _is_route_blocked(from: Transform2D, motion: Vector2) -> bool:
	_route_query.shape = _footprint.shape
	_route_query.transform = from * _footprint.transform
	_route_query.motion = motion
	_route_query.margin = safe_margin
	_route_query.collision_mask = route_obstacle_mask
	return get_world_2d().direct_space_state.cast_motion(_route_query)[0] < 1.0


func _stop() -> void:
	velocity = Vector2.ZERO
	visuals.set_motion(Vector2.ZERO)
