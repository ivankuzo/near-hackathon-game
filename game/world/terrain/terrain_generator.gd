extends RefCounted

const CHUNK_SIZE := Vector2i(12, 16)
# Chunk width fits whole patches, and height fits whole pairs of patch rows.
const ROCK_PATCH_SIZE: int = 2
const PORTAL_RADIUS: float = 150.0
const CLEARING_RADIUS: float = 225.0
# Atlas rows continue a single material over four columns and eight rows of cells.
const GROUND_PATTERN_SIZE := Vector2i(4, 8)
const MOSS_CORNERS: Array[Vector2i] = [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.ONE, Vector2i.DOWN]

var _seed: int
var _cell_size: Vector2
var _rock_noise := FastNoiseLite.new()
var _moss_noise := FastNoiseLite.new()
var _moss_threshold: float


func _init(world_seed: int, cell_size: Vector2i, moss_patch_size: float, moss_threshold: float) -> void:
	_seed = world_seed
	_cell_size = Vector2(cell_size)
	_rock_noise.seed = world_seed
	_rock_noise.frequency = 0.0018
	_rock_noise.fractal_octaves = 2
	_moss_noise.seed = world_seed ^ 0x4D4F5353
	_moss_noise.frequency = 1.0 / moss_patch_size
	_moss_noise.fractal_octaves = 2
	_moss_threshold = moss_threshold


func chunk_at(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / CHUNK_SIZE.x), floori(float(cell.y) / CHUNK_SIZE.y))


func spawn_cell() -> Vector2i:
	return _hub_cell(Vector2i.ZERO)


func ground_atlas_coords(cell: Vector2i) -> Vector2i:
	var mask: int = 0
	for index in range(MOSS_CORNERS.size()):
		# Sample shared vertices in world pixels, so patches cross chunk boundaries.
		var vertex: Vector2 = (Vector2(cell + MOSS_CORNERS[index]) - Vector2(0.5, 0.5)) * _cell_size
		if _moss_noise.get_noise_2dv(vertex) > _moss_threshold:
			mask |= 1 << index
	var pattern_row: int = posmod(cell.x, GROUND_PATTERN_SIZE.x) \
		+ GROUND_PATTERN_SIZE.x * posmod(cell.y, GROUND_PATTERN_SIZE.y)
	return Vector2i(mask, pattern_row)


func rock_cells(chunk: Vector2i) -> Dictionary[Vector2i, int]:
	var start: Vector2i = chunk * CHUNK_SIZE
	var hub: Vector2 = _cell_center(_hub_cell(chunk))
	var paths: PackedVector2Array = _paths(chunk, hub)
	var rocks: Dictionary[Vector2i, int] = {}
	var patch_size := Vector2i(ROCK_PATCH_SIZE, ROCK_PATCH_SIZE)
	for x in range(start.x, start.x + CHUNK_SIZE.x, ROCK_PATCH_SIZE):
		# Alternate stone and clear patch rows. Keep the same phase across chunk boundaries.
		var phase: int = _roll(Vector2i(x, 0), 13, 2)
		var first_row: int = start.y + phase * ROCK_PATCH_SIZE
		for y in range(first_row, start.y + CHUNK_SIZE.y, 2 * ROCK_PATCH_SIZE):
			var patch := Rect2i(Vector2i(x, y), patch_size)
			var center: Vector2 = (Vector2(patch.position) + Vector2(patch.size) * 0.5) * _cell_size
			if _rock_noise.get_noise_2dv(center) < -0.18 or _intersects_open_ground(patch, hub, paths):
				continue
			for cell_y in range(patch.position.y, patch.end.y):
				for cell_x in range(patch.position.x, patch.end.x):
					var cell := Vector2i(cell_x, cell_y)
					rocks[cell] = _roll(cell, 2, 2)
	return rocks


func _intersects_open_ground(patch: Rect2i, hub: Vector2, paths: PackedVector2Array) -> bool:
	# Keep the whole patch clear if any of its cells is part of a passage or clearing.
	for y in range(patch.position.y, patch.end.y):
		for x in range(patch.position.x, patch.end.x):
			var center: Vector2 = _cell_center(Vector2i(x, y))
			if center.distance_squared_to(hub) <= CLEARING_RADIUS * CLEARING_RADIUS or _is_on_path(center, paths):
				return true
	return false


func _paths(chunk: Vector2i, hub: Vector2) -> PackedVector2Array:
	var origin: Vector2 = Vector2(chunk * CHUNK_SIZE) * _cell_size
	var size: Vector2 = Vector2(CHUNK_SIZE) * _cell_size
	var paths := PackedVector2Array()
	for side in range(4):
		var portal: Vector2
		var inward: Vector2
		if side < 2:
			var boundary: Vector2i = chunk + Vector2i(side, 0)
			var row: int = 4 + _roll(boundary, 3, CHUNK_SIZE.y - 8)
			portal = origin + Vector2(side * size.x, (row + 0.5) * _cell_size.y)
			inward = Vector2(1 - 2 * side, 0)
		else:
			var edge: int = side - 2
			var boundary: Vector2i = chunk + Vector2i(0, edge)
			if not _has_vertical_path(boundary):
				continue
			var column: int = 2 + _roll(boundary, 4, CHUNK_SIZE.x - 4)
			portal = origin + Vector2((column + 0.5) * _cell_size.x, edge * size.y)
			inward = Vector2(0, 1 - 2 * edge)
		var entry: Vector2 = portal + inward * PORTAL_RADIUS
		var offset: float = _roll(chunk, 5 + side, 201) - 100.0
		var bend: Vector2 = entry.lerp(hub, 0.5) + inward.orthogonal() * offset
		paths.append_array(PackedVector2Array([portal, entry, entry, bend, bend, hub]))
	return paths


func _has_vertical_path(boundary: Vector2i) -> bool:
	# Every group of three columns has a connection between the two rows of chunks.
	var group := Vector2i(floori(float(boundary.x) / 3), boundary.y)
	return posmod(boundary.x, 3) == _roll(group, 9, 3) or _roll(boundary, 10, 3) == 0


func _is_on_path(point: Vector2, paths: PackedVector2Array) -> bool:
	for index in range(0, paths.size(), 2):
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, paths[index], paths[index + 1])
		if point.distance_squared_to(closest) <= PORTAL_RADIUS * PORTAL_RADIUS:
			return true
	return false


func _hub_cell(chunk: Vector2i) -> Vector2i:
	return chunk * CHUNK_SIZE + Vector2i(5 + _roll(chunk, 11, 3), 6 + _roll(chunk, 12, 5))


func _cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * _cell_size


func _roll(cell: Vector2i, salt: int, choices: int) -> int:
	return posmod(hash(Vector4i(cell.x, cell.y, _seed, salt)), choices)
