extends "res://combat/hurtbox/hurtbox.gd"

const HurtboxFrames = preload("res://combat/hurtbox/hurtbox_frames.gd")
const DEBUG_COLOR := Color(1.0, 0.31, 0.16, 0.48)

@export var frames_by_part: Dictionary[StringName, HurtboxFrames] = {}

var _owners: Dictionary[StringName, int] = {}
var _frames: Dictionary[StringName, Vector2i] = {}
var _debug_shapes: bool = false


func _ready() -> void:
	for part in frames_by_part:
		_owners[part] = create_shape_owner(self)
	_debug_shapes = get_tree().debug_collisions_hint
	if _debug_shapes:
		z_index = 5


func set_pose(part: StringName, texture: Texture2D, world_transform: Transform2D) -> void:
	if not is_active():
		return
	var atlas := texture as AtlasTexture
	if atlas == null or not frames_by_part.has(part) or frames_by_part[part] == null:
		push_error("Player hurtbox requires atlas textures and a profile for part '%s'." % part)
		deactivate()
		return
	var owner_id: int = _owners[part]
	# Profiles are centered; module sprites use the top-left corner and articulated transforms.
	var centered := Transform2D(0.0, atlas.region.size * 0.5)
	shape_owner_set_transform(owner_id, global_transform.affine_inverse() * world_transform * centered)
	var frame := Vector2i(atlas.region.position)
	if not _frames.has(part) or _frames[part] != frame:
		var shapes: Array[Shape2D] = frames_by_part[part].shapes_for(frame, false)
		if shapes.is_empty():
			push_error("Player hurtbox has no shapes for part '%s', frame %s." % [part, frame])
			deactivate()
			return
		shape_owner_clear_shapes(owner_id)
		for shape in shapes:
			shape_owner_add_shape(owner_id, shape)
		_frames[part] = frame
	if _debug_shapes:
		queue_redraw()


func deactivate() -> void:
	super.deactivate()
	if _debug_shapes:
		queue_redraw()


func _draw() -> void:
	if not _debug_shapes or not is_active():
		return
	for part in _frames:
		draw_set_transform_matrix(shape_owner_get_transform(_owners[part]))
		for shape in frames_by_part[part].shapes_for(_frames[part], false):
			shape.draw(get_canvas_item(), DEBUG_COLOR)
