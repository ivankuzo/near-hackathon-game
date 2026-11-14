extends Node2D

const SURFACE_SHADER = preload("res://world/stone/stone_fragment_surface.gdshader")
const CUT_SHADER = preload("res://world/stone/stone_fragment_cut.gdshader")
const SILHOUETTE = preload("res://world/stone/stone_silhouette.png")

const ART_SIZE := Vector2(116, 104)
const JUNCTION := Vector2(54, 41)
const CUT_COLORS: Array[Color] = [
	Color("#5e505f"), Color("#716275"), Color("#4e424f"), Color("#66586c")
]

## Base time for the larger pieces to settle, in seconds.
@export_range(0.1, 1.0, 0.01) var collapse_time: float = 0.38
## Time the settled debris remains on the ground, in seconds.
@export_range(0.0, 10.0, 0.1) var rest_time: float = 2.5
@export_range(0.05, 2.0, 0.05) var fade_time: float = 0.45
@export var contact_shadow: Texture2D

var _surface_material := ShaderMaterial.new()
var _cut_material := ShaderMaterial.new()


func _ready() -> void:
	_surface_material.shader = SURFACE_SHADER
	_surface_material.set_shader_parameter(&"silhouette_texture", SILHOUETTE)
	_cut_material.shader = CUT_SHADER


func play(
	world_origin: Vector2, texture: Texture2D, region: Rect2i, open_sides: int,
	visible_height: int, opacity: float, impact_direction: Vector2
) -> void:
	var full_height: bool = visible_height == region.size.y
	var art_height: float = ART_SIZE.y if full_height else ART_SIZE.y * 0.5
	var art_scale: Vector2 = Vector2(region.size) / ART_SIZE
	var paths: Array[PackedVector2Array] = _fracture_paths(full_height)
	var corners := PackedVector2Array([
		Vector2(ART_SIZE.x, 0), Vector2(ART_SIZE.x, art_height),
		Vector2(0, art_height), Vector2.ZERO,
	])
	var rubble := Node2D.new()
	rubble.y_sort_enabled = true
	add_child(rubble)
	rubble.global_position = world_origin
	rubble.modulate.a = opacity
	var push: Vector2 = rubble.to_local(world_origin + impact_direction).normalized()
	var visible_size := Vector2(region.size.x, visible_height)
	var landings := PackedVector2Array()
	var longest_motion: float = 0.0

	for index in range(paths.size()):
		var first: PackedVector2Array = paths[index]
		var second: PackedVector2Array = paths[(index + 1) % paths.size()]
		var outline: PackedVector2Array = first.duplicate()
		outline.append(corners[index])
		for point_index in range(second.size() - 1, 0, -1):
			outline.append(second[point_index])
		for point_index in range(outline.size()):
			outline[point_index] *= art_scale
		var bounds := Rect2(outline[0], Vector2.ZERO)
		for point in outline:
			bounds = bounds.expand(point)
		var center: Vector2 = bounds.get_center()

		var ground_anchor := Node2D.new()
		ground_anchor.position = center
		rubble.add_child(ground_anchor)
		var piece := Node2D.new()
		ground_anchor.add_child(piece)

		var cuts := Node2D.new()
		cuts.modulate.a = 0.0
		piece.add_child(cuts)
		var depth: float = clampf(bounds.size.length() * randf_range(0.15, 0.24), 8.0, 22.0)
		_add_cut_faces(cuts, first, art_scale, center, true, depth)
		_add_cut_faces(cuts, second, art_scale, center, false, depth)
		_add_surface(piece, outline, center, texture, region, open_sides)
		var landing: Vector2 = _choose_landing(center, visible_size, push, landings)
		landings.append(landing)
		longest_motion = maxf(longest_motion, _animate_piece(
			ground_anchor, piece, cuts, landing, bounds.size
		))

	var lifetime: Tween = rubble.create_tween()
	lifetime.tween_interval(longest_motion + rest_time)
	lifetime.tween_property(rubble, ^"modulate:a", 0.0, fade_time)
	lifetime.tween_callback(rubble.queue_free)


func _fracture_paths(full_height: bool) -> Array[PackedVector2Array]:
	# The arms follow the main grooves in the last damage frame.
	var south := PackedVector2Array([
		JUNCTION, Vector2(63, 46), Vector2(72, 50), Vector2(75, 52)
	])
	if full_height:
		south.append_array(PackedVector2Array([
			Vector2(78, 57), Vector2(70, 64), Vector2(65, 73), Vector2(58, 81),
			Vector2(55, 89), Vector2(49, 96), Vector2(45, 104),
		]))
	return [
		PackedVector2Array([
			JUNCTION, Vector2(50, 36), Vector2(44, 33), Vector2(35, 28),
			Vector2(32, 26), Vector2(44, 13), Vector2(39, 0),
		]),
		PackedVector2Array([
			JUNCTION, Vector2(66, 38), Vector2(77, 34), Vector2(91, 27),
			Vector2(105, 25), Vector2(116, 20),
		]),
		south,
		PackedVector2Array([
			JUNCTION, Vector2(42, 40), Vector2(32, 35), Vector2(25, 31),
			Vector2(18, 39), Vector2(9, 43), Vector2(0, 42),
		]),
	]


func _add_surface(
	piece: Node2D, outline: PackedVector2Array, center: Vector2,
	texture: Texture2D, region: Rect2i, open_sides: int
) -> void:
	var surface := Polygon2D.new()
	var vertices := PackedVector2Array()
	var uv := PackedVector2Array()
	for point in outline:
		vertices.append(point - center)
		uv.append(point + Vector2(region.position))
	surface.polygon = vertices
	surface.uv = uv
	surface.texture = texture
	var surface_material := _surface_material.duplicate() as ShaderMaterial
	surface.material = surface_material
	surface_material.set_shader_parameter(&"atlas_region", Vector4(
		region.position.x, region.position.y, region.size.x, region.size.y
	))
	surface_material.set_shader_parameter(&"open_sides", open_sides)
	piece.add_child(surface)


func _add_cut_faces(
	parent: Node2D, path: PackedVector2Array, art_scale: Vector2,
	center: Vector2, clockwise: bool, depth: float
) -> void:
	var arm: Vector2 = (path[-1] - path[0]) * art_scale
	var outward: Vector2 = (arm.orthogonal() if clockwise else -arm.orthogonal()).normalized()
	var thickness: Vector2 = (outward + Vector2(0, 0.32)) * depth
	var offset: Vector2 = thickness
	var tint: Color = CUT_COLORS[randi_range(0, CUT_COLORS.size() - 1)]
	for index in range(path.size() - 1):
		var start: Vector2 = path[index] * art_scale - center
		var end: Vector2 = path[index + 1] * art_scale - center
		var edge: Vector2 = end - start
		var normal: Vector2 = (edge.orthogonal() if clockwise else -edge.orthogonal()).normalized()
		var start_offset: Vector2 = offset
		offset = thickness * randf_range(0.76, 1.12)
		if normal.dot(thickness) <= 1.0:
			continue
		var rim_start: Vector2 = start + start_offset * 0.32
		var rim_end: Vector2 = end + offset * 0.32
		var shade: Color = tint.darkened(randf_range(0.0, 0.25))
		_add_facet(
			parent, PackedVector2Array([rim_start, rim_end, end + offset, start + start_offset]),
			shade.darkened(0.22), Vector3(normal.x, normal.y, 0.58)
		)
		_add_facet(
			parent, PackedVector2Array([start, end, rim_end, rim_start]),
			shade.lightened(0.06), Vector3(normal.x * 0.46, normal.y * 0.46, 0.88)
		)


func _add_facet(parent: Node2D, outline: PackedVector2Array, color: Color, normal: Vector3) -> void:
	var face := Polygon2D.new()
	face.polygon = outline
	face.color = color
	var facet_material := _cut_material.duplicate() as ShaderMaterial
	face.material = facet_material
	facet_material.set_shader_parameter(&"cut_normal", normal.normalized())
	parent.add_child(face)


func _choose_landing(
	start: Vector2, visible_size: Vector2, push: Vector2, occupied: PackedVector2Array
) -> Vector2:
	var radial: Vector2 = (start - visible_size * 0.5).normalized()
	var pile_center: Vector2 = visible_size * Vector2(0.5, 0.73)
	var minimum_gap: float = 22.0 + visible_size.y * 0.22
	var best := pile_center
	var best_gap: float = -1.0
	for attempt in range(5):
		var drift: Vector2 = radial.rotated(randf_range(-0.62, 0.62))
		var scatter: Vector2 = drift * randf_range(31.0, 67.0) + push * randf_range(8.0, 20.0)
		var candidate: Vector2 = pile_center + scatter * Vector2(1.0, 0.58)
		var gap: float = INF
		for point in occupied:
			gap = minf(gap, candidate.distance_to(point))
		if gap >= minimum_gap:
			return candidate
		if gap > best_gap:
			best_gap = gap
			best = candidate
	return best


func _animate_piece(
	ground_anchor: Node2D, piece: Node2D, cuts: Node2D, landing: Vector2, bounds_size: Vector2
) -> float:
	var flight: float = collapse_time * randf_range(0.72, 1.45)
	var rise: float = flight * randf_range(0.30, 0.44)
	var rebound: float = flight * randf_range(0.24, 0.46)
	var hop_height: float = randf_range(8.0, 27.0)
	var spin: float = randf_range(0.26, 1.2) * (-1.0 if randf() < 0.5 else 1.0)
	var final_scale: float = randf_range(0.63, 0.82)

	var slide: Tween = ground_anchor.create_tween().set_parallel(true)
	slide.tween_property(ground_anchor, ^"position", landing, flight + rebound) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	var motion: Tween = piece.create_tween().set_parallel(true)
	motion.tween_property(piece, ^"position:y", -hop_height, rise) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	motion.tween_property(piece, ^"rotation", spin * 0.55, rise)
	motion.tween_property(cuts, ^"modulate:a", 1.0, rise * 0.6)
	motion.chain().tween_property(piece, ^"position:y", 0.0, flight - rise) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	motion.parallel().tween_property(piece, ^"scale", Vector2.ONE * final_scale, flight - rise)
	motion.parallel().tween_property(piece, ^"rotation", spin * 0.88, flight - rise)
	var rebound_rise: float = rebound * 0.4
	motion.chain().tween_property(piece, ^"position:y", -hop_height * 0.22, rebound_rise) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	motion.parallel().tween_property(piece, ^"rotation", spin, rebound_rise) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	motion.chain().tween_property(piece, ^"position:y", 0.0, rebound - rebound_rise) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if contact_shadow != null:
		var shadow := Sprite2D.new()
		shadow.texture = contact_shadow
		shadow.position.y = bounds_size.y * final_scale * 0.25
		shadow.scale = Vector2(bounds_size.x * final_scale, 13.0) / contact_shadow.get_size()
		shadow.z_index = -1
		shadow.modulate.a = 0.0
		ground_anchor.add_child(shadow)
		slide.tween_property(shadow, ^"modulate:a", 1.0, flight * 0.6).set_delay(rise)
	return flight + rebound
