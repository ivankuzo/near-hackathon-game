extends "res://combat/hurtbox/hurtbox.gd"

const HurtboxFrames = preload("res://combat/hurtbox/hurtbox_frames.gd")
const DEBUG_COLOR := Color(1.0, 0.31, 0.16, 0.48)

@export var frames: HurtboxFrames

var _shape_owner: int
var _frame := Vector2i(-1, -1)
var _mirrored: bool = false
var _center: Vector2
var _shapes: Array[Shape2D] = []
var _debug_shapes: bool = false


func _ready() -> void:
	_shape_owner = create_shape_owner(self)
	_debug_shapes = get_tree().debug_collisions_hint
	if _debug_shapes:
		z_index = 5


func set_pose(texture: Texture2D, mirrored: bool, world_center: Vector2) -> void:
	if not is_active():
		return

	var atlas := texture as AtlasTexture
	if frames == null or atlas == null:
		push_error("Animated hurtbox requires atlas frames and a collision profile.")
		deactivate()
		return
	var frame := Vector2i(atlas.region.position)
	var center: Vector2 = to_local(world_center)
	if not center.is_equal_approx(_center):
		_center = center
		shape_owner_set_transform(_shape_owner, Transform2D(0.0, _center))
		if _debug_shapes:
			queue_redraw()
	if frame == _frame and mirrored == _mirrored:
		return

	_shapes = frames.shapes_for(frame, mirrored)
	if _shapes.is_empty():
		push_error("Animated hurtbox has no collision shapes for atlas frame %s." % frame)
		deactivate()
		return
	_frame = frame
	_mirrored = mirrored
	shape_owner_clear_shapes(_shape_owner)
	for shape in _shapes:
		shape_owner_add_shape(_shape_owner, shape)
	if _debug_shapes:
		queue_redraw()


func deactivate() -> void:
	super.deactivate()
	if _debug_shapes:
		queue_redraw()


func _draw() -> void:
	if not _debug_shapes or not is_active():
		return
	draw_set_transform(_center)
	for shape in _shapes:
		shape.draw(get_canvas_item(), DEBUG_COLOR)
