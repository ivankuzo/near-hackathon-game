extends Node2D

const OreDrops = preload("res://world/ore/ore_drops.gd")
const OreShard = preload("res://world/ore/ore_shard.gd")
const OreCollector = preload("res://world/ore/ore_collector.gd")
const EnemySpawner = preload("res://world/arena/enemy_spawner.gd")
const RobotEnemy = preload("res://enemies/robots/robot_chaser.gd")

enum Step { INACTIVE, ROCK, ORE, FIND_ENEMY, SHOW_ENEMY }

var _step: Step = Step.INACTIVE
var _stones: StoneTileMap
var _drops: OreDrops
var _collector: OreCollector
var _player: Player
var _spawner: EnemySpawner
var _ore: OreShard
var _enemy: RobotEnemy
var _marker: Rect2
var _has_marker: bool = false
var _scan_left: float = 0.0
var _notice_left: float = 0.0
var _controls_left: float = 0.0

@onready var _prompt: Label = $PromptLayer/Prompt
@onready var _controls: Control = $PromptLayer/Controls


func _ready() -> void:
	set_physics_process(false)
	_prompt.hide()
	_controls.hide()


func begin(stones: StoneTileMap, drops: OreDrops, collector: OreCollector,
		player: Player, spawner: EnemySpawner) -> void:
	_stones = stones
	_drops = drops
	_collector = collector
	_player = player
	_spawner = spawner
	_stones.stone_broken.connect(_on_stone_broken)
	_drops.ore_spawned.connect(_on_ore_spawned)
	_collector.collected.connect(_on_collected)
	_step = Step.ROCK
	_prompt.text = "BREAK THE ROCK"
	_prompt.show()
	_controls.show()
	_controls_left = 4.0
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		stop()
		return
	_scan_left -= delta
	if _controls.visible:
		_controls_left -= delta
		if _controls_left <= 0.0:
			_controls.hide()
	match _step:
		Step.ROCK:
			if _scan_left <= 0.0:
				_scan_left = 0.4
				_find_rock()
		Step.ORE:
			if is_instance_valid(_ore):
				_marker = Rect2(to_local(_ore.global_position) + Vector2(-20, -50), Vector2(40, 45))
				_has_marker = true
		Step.FIND_ENEMY:
			if _scan_left <= 0.0:
				_scan_left = 0.3
				_find_enemy()
		Step.SHOW_ENEMY:
			_notice_left -= delta
			if _notice_left <= 0.0 or not is_instance_valid(_enemy):
				stop()
				return
			_marker = Rect2(to_local(_enemy.global_position) + Vector2(-35, -80), Vector2(70, 85))
			_has_marker = true
	if _has_marker:
		var marker_top: Vector2 = get_global_transform_with_canvas() * (_marker.position + Vector2(_marker.size.x * 0.5, 0))
		var viewport_size: Vector2 = get_viewport_rect().size
		_prompt.position = Vector2(
			clampf(marker_top.x - _prompt.size.x * 0.5, 0.0, maxf(0.0, viewport_size.x - _prompt.size.x)),
			maxf(0.0, marker_top.y - _prompt.size.y - 8.0)
		).round()
	queue_redraw()


func _find_rock() -> void:
	var origin: Vector2i = _stones.world_to_cell(_player.global_position)
	var nearest_distance: float = INF
	_has_marker = false
	for y in range(-12, 13):
		for x in range(-8, 9):
			var cell: Vector2i = origin + Vector2i(x, y)
			if not _stones.is_blocked(cell):
				continue
			var center: Vector2 = _stones.cell_center(cell)
			var distance: float = center.distance_squared_to(_player.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				_marker = Rect2(to_local(center) + Vector2(-58, -78), Vector2(116, 52))
				_has_marker = true


func _find_enemy() -> void:
	if _spawner == null:
		return
	for enemy in _spawner.active_enemies():
		var screen_position: Vector2 = get_viewport().get_canvas_transform() * enemy.global_position
		if not get_viewport_rect().has_point(screen_position):
			continue
		var query := PhysicsRayQueryParameters2D.create(_player.global_position, enemy.global_position, 1)
		query.hit_from_inside = true
		if not get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			continue
		_enemy = enemy
		_step = Step.SHOW_ENEMY
		_notice_left = 3.0
		_prompt.text = "AVOID ENEMIES"
		_prompt.show()
		return


func _on_stone_broken(_cell: Vector2i, _direction: Vector2) -> void:
	if _step == Step.ROCK:
		_step = Step.ORE
		_controls.hide()
		_has_marker = false
		_prompt.hide()


func _on_ore_spawned(ore: OreShard) -> void:
	if _step == Step.ROCK or (_step == Step.ORE and not is_instance_valid(_ore)):
		_ore = ore
		_step = Step.ORE
		_controls.hide()
		_prompt.text = "COLLECT THE ORE"
		_prompt.show()


func _on_collected(_kind: StringName, _total: int, _tint: Color) -> void:
	if _step != Step.ORE:
		return
	_step = Step.FIND_ENEMY
	_has_marker = false
	_prompt.hide()
	_controls.hide()


func stop() -> void:
	_step = Step.INACTIVE
	_has_marker = false
	_prompt.hide()
	_controls.hide()
	set_physics_process(false)
	queue_redraw()
	if is_instance_valid(_stones) and _stones.stone_broken.is_connected(_on_stone_broken):
		_stones.stone_broken.disconnect(_on_stone_broken)
	if is_instance_valid(_drops) and _drops.ore_spawned.is_connected(_on_ore_spawned):
		_drops.ore_spawned.disconnect(_on_ore_spawned)
	if is_instance_valid(_collector) and _collector.collected.is_connected(_on_collected):
		_collector.collected.disconnect(_on_collected)


func _draw() -> void:
	if not _has_marker:
		return
	var color := Color(0.85, 0.93, 0.9, 0.85)
	var length: float = 10.0
	for corner in [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.ONE]:
		var point: Vector2 = _marker.position + corner * _marker.size
		var direction := Vector2(1.0 - 2.0 * corner.x, 1.0 - 2.0 * corner.y)
		draw_line(point, point + Vector2(direction.x * length, 0), color, 2.0)
		draw_line(point, point + Vector2(0, direction.y * length), color, 2.0)
