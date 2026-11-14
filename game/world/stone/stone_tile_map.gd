class_name StoneTileMap
extends Node2D

signal stone_hit(world_position: Vector2, normal: Vector2)
signal stone_cracked(cell: Vector2i)
signal stone_broken(cell: Vector2i, impact_direction: Vector2)

const STONE_SOURCE: int = 0
const SHOT_SOURCE: int = 1
const DAMAGE_STAGES: int = 3
const GroundContactShadows = preload("res://world/terrain/ground_contact_shadows.gd")
const SOUTH_EDGE: int = 8
const NEIGHBOR_EDGES: Dictionary[Vector2i, int] = {
	Vector2i.UP: 1,
	Vector2i.LEFT: 2,
	Vector2i.RIGHT: 4,
	Vector2i.DOWN: SOUTH_EDGE,
}

## Total damage required to destroy a stone cell.
@export_range(1, 1000, 1, "or_greater") var health: int = 60
@export var visuals: StoneVisuals

var _damage: Dictionary[Vector2i, int] = {}

@onready var _blocks: TileMapLayer = $Blocks
@onready var _contact_shadows: GroundContactShadows = $GroundContactShadows
@onready var _projectile_top: TileMapLayer = $ProjectileTop
@onready var _projectile_wall: TileMapLayer = $ProjectileWall
@onready var _hit_sound: AudioStreamPlayer2D = $HitSound
@onready var _crack_sound: AudioStreamPlayer2D = $CrackSound
@onready var _break_sound: AudioStreamPlayer2D = $BreakSound


func _ready() -> void:
	_projectile_top.visible = get_tree().debug_collisions_hint
	_projectile_wall.visible = get_tree().debug_collisions_hint
	_refresh_changed_cells(_blocks.get_used_cells())


func world_to_cell(world_position: Vector2) -> Vector2i:
	return _blocks.local_to_map(_blocks.to_local(world_position))


func cell_center(cell: Vector2i) -> Vector2:
	return _blocks.to_global(_blocks.map_to_local(cell))


func is_blocked(cell: Vector2i) -> bool:
	return _blocks.get_cell_source_id(cell) != -1


func update_blocks(added: Dictionary[Vector2i, int], removed: Array[Rect2i]) -> void:
	var changed: Array[Vector2i] = []
	for area in removed:
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				var cell := Vector2i(x, y)
				if _blocks.get_cell_source_id(cell) != -1:
					_blocks.erase_cell(cell)
					visuals.erase_stone(cell)
					changed.append(cell)
	for cell in added:
		if _damage.get(cell, 0) < health:
			_blocks.set_cell(cell, STONE_SOURCE, Vector2i(0, added[cell] * DAMAGE_STAGES))
			changed.append(cell)
	if not changed.is_empty():
		_refresh_changed_cells(changed)


func hit(collision: KinematicCollision2D, damage: int) -> void:
	var layer := collision.get_collider() as TileMapLayer
	if layer != _projectile_top and layer != _projectile_wall:
		return
	var cell: Vector2i = layer.get_coords_for_body_rid(collision.get_collider_rid())
	if layer == _projectile_top:
		cell += Vector2i.DOWN
	if _blocks.get_cell_source_id(cell) == -1:
		return # The physics update for an erased cell can still be queued.

	var previous_damage: int = _damage.get(cell, 0)
	var total_damage: int = previous_damage + damage
	_damage[cell] = total_damage
	if total_damage >= health:
		_play_sound(_break_sound, collision.get_position())
		stone_broken.emit(cell, -collision.get_normal())
		update_blocks({}, [Rect2i(cell, Vector2i.ONE)])
		return
	_update_stone(cell)
	if _damage_stage(total_damage) != _damage_stage(previous_damage):
		_play_sound(_crack_sound, collision.get_position())
		stone_cracked.emit(cell)
	else:
		_play_sound(_hit_sound, collision.get_position())
	stone_hit.emit(collision.get_position(), collision.get_normal())


func _play_sound(player: AudioStreamPlayer2D, world_position: Vector2) -> void:
	player.global_position = world_position
	player.play()


func _damage_stage(damage: int) -> int:
	return floori(float(DAMAGE_STAGES * damage) / health)


func _refresh_changed_cells(changed: Array[Vector2i]) -> void:
	var stones: Dictionary[Vector2i, bool] = {}
	var surfaces: Dictionary[Vector2i, bool] = {}
	for cell in changed:
		var roof: Vector2i = cell + Vector2i.UP
		stones[cell] = true
		surfaces[cell] = true
		surfaces[roof] = true
		for offset in NEIGHBOR_EDGES:
			var neighbor: Vector2i = cell + offset
			stones[neighbor] = true
			surfaces[neighbor] = true
			surfaces[roof + offset] = true
			if offset.x != 0:
				stones[neighbor + Vector2i.UP] = true
				stones[neighbor + Vector2i.DOWN] = true
	for cell in stones:
		if _blocks.get_cell_source_id(cell) != -1:
			_update_stone(cell)
	for cell in surfaces:
		_update_projectile_cell(cell)
	_contact_shadows.update_cells(_blocks, stones.keys())
	visuals.refresh_occlusion()


func _update_stone(cell: Vector2i) -> void:
	var edges: int = 0
	# The front occupies this cell. Only the roof directly south can cover it.
	for offset in NEIGHBOR_EDGES:
		if _blocks.get_cell_source_id(cell + offset) == -1:
			edges |= NEIGHBOR_EDGES[offset]

	# Atlas columns are edge masks. Rows are grouped by variant, then damage stage.
	var damage: int = _damage.get(cell, 0)
	var stage: int = _damage_stage(damage)
	var original: Vector2i = _blocks.get_cell_atlas_coords(cell)
	var first_row: int = original.y - posmod(original.y, DAMAGE_STAGES)
	var atlas := Vector2i(edges, first_row + stage)
	var alternative: int = _open_projected_sides(cell + Vector2i.UP)
	if (edges & SOUTH_EDGE) != 0:
		alternative |= _open_projected_sides(cell) << 2
		# A neighboring roof meets this front when its block sits one row south.
		if _blocks.get_cell_source_id(cell + Vector2i(-1, 1)) != -1:
			alternative |= 16
		if _blocks.get_cell_source_id(cell + Vector2i(1, 1)) != -1:
			alternative |= 32
	visuals.set_stone(cell, atlas, alternative)


func _open_projected_sides(cell: Vector2i) -> int:
	var west: int = 0 if _has_projected_stone(cell + Vector2i.LEFT) else 1
	var east: int = 0 if _has_projected_stone(cell + Vector2i.RIGHT) else 2
	return west | east


func _has_projected_stone(cell: Vector2i) -> bool:
	return _blocks.get_cell_source_id(cell) != -1 or _blocks.get_cell_source_id(cell + Vector2i.DOWN) != -1


func _update_projectile_cell(cell: Vector2i) -> void:
	# In projected space the roof of the southern block takes the place of this wall.
	var has_top: bool = _blocks.get_cell_source_id(cell + Vector2i.DOWN) != -1
	var has_wall: bool = not has_top and _blocks.get_cell_source_id(cell) != -1
	var edges: int = 0
	if has_top or has_wall:
		for offset in NEIGHBOR_EDGES:
			if not _has_projected_stone(cell + offset):
				edges |= NEIGHBOR_EDGES[offset]
	var atlas := Vector2i(edges, 0)
	_projectile_top.set_cell(cell, SHOT_SOURCE if has_top else -1, atlas)
	_projectile_wall.set_cell(cell, SHOT_SOURCE if has_wall else -1, atlas)
