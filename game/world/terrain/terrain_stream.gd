class_name TerrainStream
extends Node2D

signal blocks_changed(added: Dictionary[Vector2i, int], removed: Array[Rect2i])

const TerrainGenerator = preload("res://world/terrain/terrain_generator.gd")

@export var world_seed: int = 84217
## World pixels loaded beyond the view to cover projectile travel and camera lag.
@export_range(0.0, 2000.0, 1.0, "or_greater") var stream_margin: float = 760.0
## Approximate size of moss patches in world pixels.
@export_range(116.0, 2000.0, 1.0, "or_greater") var moss_patch_size: float = 620.0
## Higher values leave more exposed earth; lower values grow more moss.
@export_range(-1.0, 1.0, 0.01) var moss_threshold: float = 0.08

var _terrain: TerrainGenerator
var _loaded_chunks := Rect2i()

@onready var _floor: TileMapLayer = $Floor


func _ready() -> void:
	_terrain = TerrainGenerator.new(world_seed, _floor.tile_set.tile_size, moss_patch_size, moss_threshold)


func spawn_position() -> Vector2:
	return _floor.to_global(_floor.map_to_local(_terrain.spawn_cell()))


func loaded_cell_bounds() -> Rect2i:
	return Rect2i(
		_loaded_chunks.position * TerrainGenerator.CHUNK_SIZE,
		_loaded_chunks.size * TerrainGenerator.CHUNK_SIZE
	)


func update_around(world_position: Vector2, view_half_extent: Vector2) -> void:
	var player_position: Vector2 = _floor.to_local(world_position)
	var padding: Vector2 = view_half_extent + Vector2.ONE * stream_margin
	var first: Vector2i = _terrain.chunk_at(_floor.local_to_map(player_position - padding))
	var last: Vector2i = _terrain.chunk_at(_floor.local_to_map(player_position + padding))
	var needed := Rect2i(first, last - first + Vector2i.ONE)
	if needed == _loaded_chunks:
		return

	var unloaded: Array[Rect2i] = []
	for y in range(_loaded_chunks.position.y, _loaded_chunks.end.y):
		for x in range(_loaded_chunks.position.x, _loaded_chunks.end.x):
			var chunk := Vector2i(x, y)
			if not needed.has_point(chunk):
				var cells := Rect2i(chunk * TerrainGenerator.CHUNK_SIZE, TerrainGenerator.CHUNK_SIZE)
				unloaded.append(cells)
				_set_ground(cells, false)

	var rocks: Dictionary[Vector2i, int] = {}
	for y in range(needed.position.y, needed.end.y):
		for x in range(needed.position.x, needed.end.x):
			var chunk := Vector2i(x, y)
			if not _loaded_chunks.has_point(chunk):
				_set_ground(Rect2i(chunk * TerrainGenerator.CHUNK_SIZE, TerrainGenerator.CHUNK_SIZE), true)
				rocks.merge(_terrain.rock_cells(chunk))
	blocks_changed.emit(rocks, unloaded)
	_loaded_chunks = needed


func _set_ground(area: Rect2i, loaded: bool) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if loaded:
				_floor.set_cell(cell, 0, _terrain.ground_atlas_coords(cell))
			else:
				_floor.erase_cell(cell)
