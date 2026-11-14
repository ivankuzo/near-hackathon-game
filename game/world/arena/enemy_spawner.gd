extends Node2D

const SpawnEntry = preload("res://world/arena/enemy_spawn_entry.gd")
const RobotEnemy = preload("res://enemies/robots/robot_chaser.gd")
const ChaseRoutes = preload("res://world/arena/chase_routes.gd")

signal enemy_spawned(enemy: RobotEnemy)

class Encounter:
	var scene: PackedScene
	var world_position: Vector2
	var dormant: bool
	var seed_value: int
	var health: int = -1

@export_group("Encounter Mix")
@export var entries: Array[SpawnEntry] = []
## One roll for each sector, independently of the enemy type weights.
@export_range(0.0, 1.0, 0.01) var encounter_chance: float = 0.46
@export_range(0.0, 1.0, 0.01) var dormant_chance: float = 0.55

@export_group("Placement")
## Size of one encounter sector in terrain cells.
@export var sector_size := Vector2i(4, 4)
## Minimum distance from the start point to an encounter.
@export_range(0.0, 2000.0, 1.0, "suffix:px") var safe_radius: float = 320.0
## Extra distance outside the viewport at which enemies are instantiated.
@export_range(0.0, 1200.0, 1.0, "suffix:px") var stream_margin: float = 170.0

@export_group("Level References")
@export var terrain: TerrainStream
@export var stones: StoneTileMap
@export var observer: Node2D
@export var headlamp: PointLight2D

var _routes: ChaseRoutes
var _beam: Image
var _start: Vector2
var _weight_total: float = 0.0
var _encounter_seed: int
var _active_area := Rect2i()
var _terrain_area := Rect2i()
var _encounters: Dictionary[Vector2i, Encounter] = {}
var _active: Dictionary[Vector2i, RobotEnemy] = {}


func start() -> void:
	if _routes != null:
		return
	if terrain == null or stones == null or observer == null or sector_size.x < 1 or sector_size.y < 1:
		push_error("Enemy spawner requires terrain, stones, an observer and a positive sector size.")
		return
	_weight_total = 0.0
	for entry in entries:
		if entry == null or entry.weight <= 0.0:
			continue
		if entry.enemy_scene == null:
			push_error("Enemy spawner has a weighted entry with no scene.")
			return
		_weight_total += entry.weight
	if _weight_total <= 0.0:
		push_error("Enemy spawner requires at least one enemy scene with a positive weight.")
		return
	_start = observer.global_position
	_encounter_seed = randi()
	_routes = ChaseRoutes.new(stones)
	if headlamp != null and headlamp.texture != null:
		_beam = headlamp.texture.get_image()


func update_around(world_position: Vector2, half_extent: Vector2) -> void:
	if _routes == null:
		return
	var padding: Vector2 = half_extent + Vector2.ONE * stream_margin
	var first: Vector2i = _sector_at(stones.world_to_cell(world_position - padding))
	var last: Vector2i = _sector_at(stones.world_to_cell(world_position + padding))
	var needed := Rect2i(first, last - first + Vector2i.ONE)
	var loaded: Rect2i = terrain.loaded_cell_bounds()
	if needed == _active_area and loaded == _terrain_area:
		return
	_active_area = needed
	_terrain_area = loaded

	# Keep pursued robots alive while their current position remains near the viewport.
	var retained: Rect2i = needed.grow(1)
	for sector in _active.keys():
		var active_enemy: Variant = _active[sector]
		if not is_instance_valid(active_enemy) or active_enemy.is_queued_for_deletion():
			_active.erase(sector)
			_encounters[sector] = null
			continue
		var enemy: RobotEnemy = active_enemy
		if retained.has_point(_sector_at(stones.world_to_cell(enemy.global_position))):
			continue
		if enemy.is_defeated():
			_encounters[sector] = null
		else:
			_encounters[sector].dormant = enemy.is_dormant()
			_encounters[sector].health = enemy.current_health
			_encounters[sector].world_position = enemy.global_position
		_active.erase(sector)
		enemy.queue_free()

	for y in range(needed.position.y, needed.end.y):
		for x in range(needed.position.x, needed.end.x):
			var sector := Vector2i(x, y)
			if _active.has(sector):
				continue
			var area := Rect2i(sector * sector_size, sector_size)
			if not loaded.encloses(area.grow(1)):
				continue
			if not _encounters.has(sector):
				_encounters[sector] = _choose_encounter(sector, area)

	for sector in _encounters:
		var encounter: Encounter = _encounters[sector]
		if encounter == null or _active.has(sector):
			continue
		var cell: Vector2i = stones.world_to_cell(encounter.world_position)
		if needed.has_point(_sector_at(cell)) and loaded.has_point(cell):
			_spawn(sector, encounter)


func _sector_at(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / sector_size.x), floori(float(cell.y) / sector_size.y))


func active_enemies() -> Array[RobotEnemy]:
	var enemies: Array[RobotEnemy] = []
	for enemy in _active.values():
		if is_instance_valid(enemy) and not enemy.is_defeated():
			enemies.append(enemy)
	return enemies


func _choose_encounter(sector: Vector2i, area: Rect2i) -> Encounter:
	var random := RandomNumberGenerator.new()
	random.seed = hash(Vector4i(_encounter_seed, sector.x, sector.y, 901))
	if random.randf() >= encounter_chance:
		return null
	var spawnable: Array[Vector2] = []
	var sheltered: Array[Vector2] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			var center: Vector2 = stones.cell_center(cell)
			if center.distance_squared_to(_start) < safe_radius * safe_radius:
				continue
			if not stones.is_blocked(cell) and not stones.is_blocked(cell + Vector2i.DOWN):
				spawnable.append(center)
				var nearby_walls: int = 0
				for direction in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
					if stones.is_blocked(cell + direction):
						nearby_walls += 1
				if nearby_walls >= 1:
					sheltered.append(center)
	if spawnable.is_empty():
		return null

	var encounter := Encounter.new()
	encounter.scene = _pick_scene(random.randf() * _weight_total)
	encounter.dormant = random.randf() < dormant_chance
	var candidates: Array[Vector2] = sheltered if encounter.dormant and not sheltered.is_empty() else spawnable
	encounter.world_position = candidates[random.randi_range(0, candidates.size() - 1)]
	encounter.seed_value = random.randi()
	return encounter


func _pick_scene(roll: float) -> PackedScene:
	var last: PackedScene
	for entry in entries:
		if entry == null or entry.weight <= 0.0:
			continue
		last = entry.enemy_scene
		roll -= entry.weight
		if roll < 0.0:
			break
	return last


func _spawn(sector: Vector2i, encounter: Encounter) -> void:
	var instance: Node = encounter.scene.instantiate()
	var enemy := instance as RobotEnemy
	if enemy == null:
		push_error("Enemy spawner entries must use a robot enemy scene.")
		instance.free()
		_encounters[sector] = null
		return
	enemy.position = to_local(encounter.world_position)
	add_child(enemy)
	if not enemy.activate(
		observer, _routes.find_route, encounter.dormant, encounter.seed_value, encounter.health
	):
		enemy.queue_free()
		_encounters[sector] = null
		return
	_active[sector] = enemy
	enemy.visuals.set_shadow_light(headlamp, _beam)
	enemy_spawned.emit(enemy)
