class_name RobotVisual
extends Node2D

signal hurtbox_pose_changed(part: StringName, texture: Texture2D, world_transform: Transform2D)

const Catalog = preload("res://player/robot_catalog.gd")
const WalkMotion = preload("res://player/walk_motion.gd")

var _forearm_rest_angle: float = 0.0
var _headlamp_offset: Vector2

@onready var _walk_motion: WalkMotion = $WalkMotion
@onready var _origin: Node2D = $CanvasOrigin
@onready var _legs: AnimatedSprite2D = $CanvasOrigin/Legs
@onready var _body: Sprite2D = $CanvasOrigin/Body
@onready var _head: Sprite2D = $CanvasOrigin/Head
@onready var _left: AnimatedSprite2D = $CanvasOrigin/LeftTool
@onready var _shoulder: Node2D = $CanvasOrigin/RightShoulder
@onready var _upper_arm: Sprite2D = $CanvasOrigin/RightShoulder/UpperArm
@onready var _elbow: Node2D = $CanvasOrigin/RightShoulder/Elbow
@onready var _forearm: Sprite2D = $CanvasOrigin/RightShoulder/Elbow/Forearm
@onready var _muzzle: Marker2D = $CanvasOrigin/RightShoulder/Elbow/Forearm/Muzzle


func apply_loadout(
	loadout: Dictionary[String, String], slot_offsets: Dictionary[String, Vector2] = {}
) -> bool:
	var modules: Dictionary[String, Dictionary] = {}
	for slot in Catalog.slots():
		var id: String = loadout.get(slot, "")
		var choices: Dictionary = Catalog.variants(slot)
		if not choices.has(id):
			push_error("Unknown robot module '%s' for slot '%s'." % [id, slot])
			return false
		modules[slot] = choices[id]

	var legs: SpriteFrames = load(modules["legs"]["sprite_frames"]) as SpriteFrames
	var body: Texture2D = load(modules["body"]["texture"]) as Texture2D
	var head: Texture2D = load(modules["head"]["texture"]) as Texture2D
	var left: SpriteFrames = load(modules["left_tool"]["sprite_frames"]) as SpriteFrames
	var right: Dictionary = modules["right_tool"]
	var upper: Texture2D = load(right["parts"]["upper_arm"]["texture"]) as Texture2D
	var forearm: Texture2D = load(right["parts"]["forearm"]["texture"]) as Texture2D
	if not legs or not body or not head or not left or not upper or not forearm:
		push_error("Could not load all art resources for the robot loadout.")
		return false

	_legs.sprite_frames = legs
	_body.texture = body
	_head.texture = head
	_headlamp_offset = Catalog.point(modules["head"]["light_origin"])
	_left.sprite_frames = left
	_upper_arm.texture = upper
	_forearm.texture = forearm

	# The atlas cells share one canvas. Subtracting each pivot keeps its pixels registered.
	var shoulder: Vector2 = Catalog.mount("right_shoulder")
	var elbow: Vector2 = Catalog.point(right["elbow"])
	var right_offset: Vector2 = slot_offsets.get("right_tool", Vector2.ZERO)
	_shoulder.position = shoulder + right_offset
	_upper_arm.position = -shoulder
	_elbow.position = elbow - shoulder
	_elbow.rotation = 0.0
	_forearm.position = -elbow
	_muzzle.position = Catalog.point(right["aim_tip"])
	_forearm_rest_angle = (_muzzle.position - elbow).angle()
	_legs.position = slot_offsets.get("legs", Vector2.ZERO)
	_body.position = slot_offsets.get("body", Vector2.ZERO)
	_head.position = slot_offsets.get("head", Vector2.ZERO)
	_left.position = slot_offsets.get("left_tool", Vector2.ZERO)
	_left.rotation = 0.0
	_origin.position = -Catalog.point(modules["legs"]["ground_anchor"]) if slot_offsets.is_empty() else Vector2.ZERO
	_legs.play(&"idle")
	_left.play(&"idle")
	return _walk_motion.capture_rest_pose(loadout["legs"], Catalog.mount("left_shoulder"))


func aim_at(world_position: Vector2) -> void:
	var horizontal_offset: float = world_position.x - global_position.x
	# The unmirrored sprites face left.
	var should_mirror: bool = horizontal_offset > 0.0
	var is_mirrored: bool = transform.x.x < 0.0
	if not is_zero_approx(horizontal_offset) and should_mirror != is_mirrored:
		transform = transform.scaled_local(Vector2(-1.0, 1.0))

	# The shoulder's local -X points inward on both sides of the robot.
	var direction: Vector2 = _shoulder.to_local(world_position) - _elbow.position
	direction.x = minf(direction.x, 0.0)
	if not direction.is_zero_approx():
		_elbow.rotation = direction.angle() - _forearm_rest_angle


func muzzle_position() -> Vector2:
	return _muzzle.global_position


func publish_hurtbox_pose() -> void:
	hurtbox_pose_changed.emit(&"legs", _legs.sprite_frames.get_frame_texture(
			_legs.animation, _legs.frame), _legs.global_transform)
	hurtbox_pose_changed.emit(&"body", _body.texture, _body.global_transform)
	hurtbox_pose_changed.emit(&"head", _head.texture, _head.global_transform)
	hurtbox_pose_changed.emit(&"left_tool", _left.sprite_frames.get_frame_texture(
			_left.animation, _left.frame), _left.global_transform)
	hurtbox_pose_changed.emit(&"upper_arm", _upper_arm.texture, _upper_arm.global_transform)
	hurtbox_pose_changed.emit(&"forearm", _forearm.texture, _forearm.global_transform)


func headlamp_position() -> Vector2:
	return _head.to_global(_headlamp_offset)


func scatter_modules(parent: Node2D) -> void:
	var parts: Array[Node2D] = [_legs, _body, _head, _left, _upper_arm, _forearm]
	var directions: Array[Vector2] = [
		Vector2(-0.4, 0.5), Vector2(0.2, -0.45), Vector2(0.25, -1.0),
		Vector2(-1.0, -0.3), Vector2(0.75, -0.5), Vector2(1.0, 0.2),
	]
	for i in range(parts.size()):
		var source: Node2D = parts[i]
		var texture: Texture2D
		var animated := source as AnimatedSprite2D
		var sprite := source as Sprite2D
		if animated != null:
			texture = animated.sprite_frames.get_frame_texture(animated.animation, animated.frame)
		elif sprite != null:
			texture = sprite.texture
		assert(texture != null, "Robot module needs a texture for the defeat effect.")
		var piece := Sprite2D.new()
		piece.texture = texture
		piece.light_mask = 10
		piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		parent.add_child(piece)
		piece.global_transform = source.global_transform * Transform2D(0.0, texture.get_size() * 0.5)
		var motion: Tween = piece.create_tween().set_parallel()
		motion.tween_property(piece, ^"global_position", piece.global_position + directions[i] * 48.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		motion.tween_property(piece, ^"rotation", piece.rotation + (0.45 if i % 2 == 0 else -0.45), 0.7)
		motion.tween_property(piece, ^"modulate:a", 0.0, 0.4).set_delay(0.7)
	hide()


func set_walking(walking: bool) -> void:
	var clip: StringName = &"walk" if walking else &"idle"
	if _legs.animation != clip:
		_legs.play(clip)


func advance_walk(delta: float) -> void:
	_walk_motion.advance(delta)
