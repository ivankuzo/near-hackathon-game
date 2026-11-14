extends Node

@export var legs: AnimatedSprite2D
@export var body: Node2D
@export var head: Node2D
@export var free_arm: Node2D
@export var weapon_shoulder: Node2D
## Per chassis: lift and lateral sway in pixels, free-arm swing in degrees.
@export var chassis_motion: Dictionary[String, Vector3] = {}
## Time to blend into or out of walking, in seconds.
@export_range(0.01, 0.5, 0.01, "suffix:s") var blend_time: float = 0.12
@export_range(0.0, 1.0, 0.05) var head_follow: float = 0.55

var _profile: Vector3
var _body_rest: Vector2
var _head_rest: Vector2
var _arm_rest: Transform2D
var _arm_pivot: Vector2
var _shoulder_rest: Vector2
var _weight: float = 0.0
var _phase: float = 0.0


func capture_rest_pose(chassis: String, arm_pivot: Vector2) -> bool:
	if legs == null or body == null or head == null or free_arm == null or weapon_shoulder == null:
		push_error("WalkMotion requires its module nodes assigned in the scene.")
		return false
	if not chassis_motion.has(chassis):
		push_error("No walk motion configured for chassis '%s'." % chassis)
		return false
	_profile = chassis_motion[chassis]
	_body_rest = body.position
	_head_rest = head.position
	_arm_rest = free_arm.transform
	_arm_pivot = arm_pivot
	_shoulder_rest = weapon_shoulder.position
	_weight = 0.0
	_phase = 0.0
	return true


## Called before aiming and publishing hurtboxes so all transforms use the same pose.
func advance(delta: float) -> void:
	var walking: bool = legs.animation == &"walk" and legs.is_playing()
	_weight = move_toward(_weight, 1.0 if walking else 0.0, delta / blend_time)
	if walking:
		var frame_count: int = legs.sprite_frames.get_frame_count(&"walk")
		_phase = TAU * (float(legs.frame) + legs.frame_progress) / float(frame_count)
	var stride: float = sin(_phase + PI * 0.25)
	# Contact poses are frames 0 and 2; passing poses 1 and 3 lift the torso.
	var lift: float = -_profile.x * (0.5 - 0.5 * cos(_phase * 2.0))
	var torso := Vector2(stride * _profile.y, lift) * _weight
	var arm_angle: float = deg_to_rad(-stride * _profile.z) * _weight
	# Quantize only the added motion, preserving the authored mounts and module offsets.
	body.position = _body_rest + torso.round()
	head.position = _head_rest + (torso * head_follow).round()
	# Rotate around the authored shoulder socket, keeping the arm attached to the body.
	var arm_swing := Transform2D(arm_angle, _arm_pivot - _arm_pivot.rotated(arm_angle))
	free_arm.transform = Transform2D(0.0, torso.round()) * _arm_rest * arm_swing
	weapon_shoulder.position = _shoulder_rest + torso.round()
