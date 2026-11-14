extends Node

const RobotVisuals = preload("res://enemies/robots/robot_enemy_visual.gd")

@export var visuals: RobotVisuals
@export_range(1, 100, 1) var damage: int = 8
## Maximum distance between enemy and player ground positions, in pixels.
@export_range(1.0, 150.0, 1.0, "suffix:px") var attack_range: float = 48.0
@export_range(0.1, 5.0, 0.1, "suffix:s") var interval: float = 1.1
@export_range(0.0, 20.0, 1.0, "suffix:px") var lunge_distance: float = 4.0
@export_flags_2d_physics var obstacle_mask: int = 1

var _remaining: float = 0.0
var _lunge: Tween
var _visual_rest: Vector2


func _ready() -> void:
	assert(visuals != null, "Melee attack requires robot visuals.")
	_visual_rest = visuals.position


func update_attack(attacker: Node2D, target: Player, delta: float) -> void:
	_remaining = maxf(0.0, _remaining - delta)
	if _remaining > 0.0:
		return
	var offset: Vector2 = target.global_position - attacker.global_position
	if offset.length_squared() > attack_range * attack_range:
		return
	if not offset.is_zero_approx():
		var query := PhysicsRayQueryParameters2D.create(
				attacker.global_position, target.global_position, obstacle_mask)
		query.hit_from_inside = true
		if not attacker.get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			return
	_remaining = interval
	var direction: Vector2 = offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT
	target.receive_melee_hit(damage, direction)
	if _lunge != null:
		_lunge.kill()
	_lunge = create_tween()
	_lunge.tween_method(_set_visual_position, _visual_rest, _visual_rest + direction * lunge_distance, 0.1)
	_lunge.tween_method(_set_visual_position, _visual_rest + direction * lunge_distance, _visual_rest, 0.18)


func stop() -> void:
	if _lunge != null:
		_lunge.kill()
	_set_visual_position(_visual_rest)


func _set_visual_position(value: Vector2) -> void:
	visuals.position = value.round()
	visuals.publish_hurtbox_pose()
