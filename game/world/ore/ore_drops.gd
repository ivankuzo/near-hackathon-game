extends Node2D

const OreShard = preload("res://world/ore/ore_shard.gd")

signal ore_spawned(ore: OreShard)

@export var stones: StoneTileMap
@export var iron_scene: PackedScene = preload("res://world/ore/iron.tscn")
@export var copper_scene: PackedScene = preload("res://world/ore/copper.tscn")
@export var cobalt_scene: PackedScene = preload("res://world/ore/cobalt.tscn")
## Chance per broken stone for each ore type.
@export_range(0.0, 1.0, 0.01) var iron_chance: float = 0.20
@export_range(0.0, 1.0, 0.01) var copper_chance: float = 0.08
@export_range(0.0, 1.0, 0.01) var cobalt_chance: float = 0.04
@export_range(0.0, 60.0, 1.0, "suffix:px") var scatter_radius: float = 22.0

var _guarantee_next_drop: bool = false


func _ready() -> void:
	if stones == null:
		push_error("OreDrops: stone map is not assigned.")
		return
	if iron_scene == null or copper_scene == null or cobalt_scene == null:
		push_error("OreDrops: an ore scene is missing.")
		return
	if iron_chance < 0.0 or copper_chance < 0.0 or cobalt_chance < 0.0:
		push_error("Ore drop chances cannot be negative.")
		return
	if iron_chance + copper_chance + cobalt_chance > 1.0:
		push_error("Ore drop chances cannot total more than 1.0.")
		return
	stones.stone_broken.connect(_on_stone_broken)


func guarantee_first_drop() -> void:
	_guarantee_next_drop = true


func get_ore_scenes() -> Array[PackedScene]:
	return [iron_scene, copper_scene, cobalt_scene]


func _on_stone_broken(cell: Vector2i, impact_direction: Vector2) -> void:
	var selected: PackedScene
	if _guarantee_next_drop:
		_guarantee_next_drop = false
		selected = iron_scene
	else:
		var roll: float = randf()
		if roll < iron_chance:
			selected = iron_scene
		elif roll < iron_chance + copper_chance:
			selected = copper_scene
		elif roll < iron_chance + copper_chance + cobalt_chance:
			selected = cobalt_scene
	if selected == null:
		return
	var instance: Node = selected.instantiate()
	var ore := instance as OreShard
	if ore == null:
		push_error("OreDrops entries must use an ore shard scene.")
		instance.free()
		return
	var center: Vector2 = stones.cell_center(cell)
	var angle: float = randf_range(0.0, TAU)
	var distance: float = randf_range(0.5, 1.0) * scatter_radius
	var offset := Vector2(cos(angle), sin(angle) * 0.55) * distance
	offset += impact_direction.normalized() * scatter_radius * 0.3
	var landing: Vector2 = center + offset
	var landing_cell: Vector2i = stones.world_to_cell(landing)
	# The destroyed cell is still present while stone_broken is being emitted.
	if landing_cell != cell and stones.is_blocked(landing_cell):
		landing = center
	# Prefer an exposed neighboring cell on the side the shot came from.
	var best_alignment: float = -INF
	for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var neighbor: Vector2i = cell + direction
		var foreground: Vector2i = neighbor + Vector2i.DOWN
		if stones.is_blocked(neighbor) or (foreground != cell and stones.is_blocked(foreground)):
			continue
		var alignment: float = Vector2(direction).dot(-impact_direction.normalized())
		if alignment > best_alignment:
			best_alignment = alignment
			landing = stones.cell_center(neighbor)
	add_child(ore)
	ore.launch(center, landing)
	ore_spawned.emit(ore)
