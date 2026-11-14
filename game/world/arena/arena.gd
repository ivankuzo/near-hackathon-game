class_name Arena
extends Node2D

signal run_finished(won: bool, ore: Dictionary)

const EnemySpawner = preload("res://world/arena/enemy_spawner.gd")

const OreCollector = preload("res://world/ore/ore_collector.gd")
const OreCounters = preload("res://ui/ore/ore_counters.gd")
const HealthBar = preload("res://ui/health/health_bar.gd")
const RobotEnemy = preload("res://enemies/robots/robot_chaser.gd")
const DamageVignette = preload("res://ui/damage_vignette.gd")
const FailScreen = preload("res://ui/fail_screen.gd")
const OreDrops = preload("res://world/ore/ore_drops.gd")
const OreShard = preload("res://world/ore/ore_shard.gd")
const Onboarding = preload("res://ui/onboarding.gd")

@export var ore_collector: OreCollector
@export var ore_counters: OreCounters
@export var camera: Camera2D
@export var terrain: TerrainStream
@export var stone_map: StoneTileMap
@export var player: Player
@export var enemy_spawner: EnemySpawner
@export var ore_drops: OreDrops
## Run duration in seconds; zero disables the timer.
@export_range(0.0, 600.0, 1.0, "suffix:s") var run_duration: float = 300.0
## Onboarding run duration in seconds.
@export_range(1.0, 600.0, 1.0, "suffix:s") var onboarding_duration: float = 180.0
## Minimum enemy spawn distance during onboarding.
@export_range(0.0, 2000.0, 1.0, "suffix:px") var onboarding_safe_radius: float = 500.0
## Chance that an ore drop wakes the nearest sleeping enemy on screen.
@export_range(0.0, 1.0, 0.01) var ore_wake_chance: float = 0.35

@onready var _health_bar: HealthBar = $Instructions/Health
@onready var _run_timer_label: Label = $Instructions/RunTimer
@onready var _survive_hint: Label = $Instructions/SurviveHint
@onready var _enemy_death_shake: CameraShakeSource = $EnemyDeathShake
@onready var _player_damage_shake: CameraShakeSource = $PlayerDamageShake
@onready var _damage_vignette: DamageVignette = $Instructions/DamageVignette
@onready var _fail_screen: FailScreen = $Instructions/FailScreen
@onready var _fail_shake: CameraShakeSource = $FailShake
@onready var _onboarding: Onboarding = $Onboarding
@onready var _light_budget: Node = $LightBudget
var _time_left: float
var _active_run_duration: float
var _finished: bool = false
var onboarding_enabled: bool = false


func _ready() -> void:
	player.health_changed.connect(_health_bar.set_health)
	player.health_changed.connect(_on_player_health_changed)
	player.damage_received.connect(_player_damage_shake.trigger)
	player.damage_received.connect(_damage_vignette.flash)
	_fail_screen.impact.connect(_fail_shake.trigger)
	_fail_screen.finished.connect(_on_fail_finished)
	_health_bar.set_health(player.current_health, player.max_health)
	_active_run_duration = onboarding_duration if onboarding_enabled else run_duration
	_time_left = _active_run_duration
	_run_timer_label.visible = _active_run_duration > 0.0
	_survive_hint.visible = _run_timer_label.visible
	_update_timer_label()
	if _run_timer_label.visible:
		_show_timer_hint()
	ore_collector.collected.connect(ore_counters.update_amount)
	ore_drops.ore_spawned.connect(_on_ore_spawned)
	player.global_position = terrain.spawn_position()
	stone_map.visuals.observer = player
	camera.limit_enabled = false
	camera.reset_smoothing()
	if enemy_spawner != null:
		if onboarding_enabled:
			enemy_spawner.safe_radius = maxf(enemy_spawner.safe_radius, onboarding_safe_radius)
		enemy_spawner.enemy_spawned.connect(_on_enemy_spawned)
		enemy_spawner.start()
	_update_terrain()


func _process(delta: float) -> void:
	if _finished:
		return
	if _active_run_duration > 0.0:
		_time_left = maxf(0.0, _time_left - delta)
		_update_timer_label()
		if _time_left <= 0.0:
			_finish_run(true)
			return
	_update_terrain()


func _update_timer_label() -> void:
	var seconds: int = ceili(_time_left)
	_run_timer_label.text = "%02d:%02d" % [floori(float(seconds) / 60.0), seconds % 60]


func _show_timer_hint() -> void:
	var font: Font = _run_timer_label.get_theme_font(&"font")
	var font_size: int = _run_timer_label.get_theme_font_size(&"font_size")
	var hint_width: float = font.get_string_size(_survive_hint.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var timer_width: float = font.get_string_size(_run_timer_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var gap: float = 8.0
	_survive_hint.offset_left = -(hint_width + gap + timer_width) / 2.0
	_survive_hint.offset_right = _survive_hint.offset_left + hint_width
	var timer_shift: float = (hint_width + gap) / 2.0
	var final_left: float = _run_timer_label.offset_left
	var final_right: float = _run_timer_label.offset_right
	_run_timer_label.offset_left += timer_shift
	_run_timer_label.offset_right += timer_shift
	var tween: Tween = create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(_survive_hint, ^"modulate:a", 0.0, 0.3)
	tween.parallel().tween_property(_run_timer_label, ^"offset_left", final_left, 0.3)
	tween.parallel().tween_property(_run_timer_label, ^"offset_right", final_right, 0.3)
	tween.tween_callback(_survive_hint.hide)


func _on_player_health_changed(current: int, _maximum: int) -> void:
	if current <= 0:
		_finish_run(false)


func _finish_run(won: bool) -> void:
	if _finished:
		return
	_finished = true
	_onboarding.stop()
	if won:
		var ore: Dictionary = ore_collector.amounts.duplicate()
		run_finished.emit(true, ore)
	else:
		player.set_physics_process(false)
		player.call_deferred(&"scatter_on_defeat", $DeathDebris)
		if enemy_spawner != null:
			enemy_spawner.set_deferred(&"process_mode", Node.PROCESS_MODE_DISABLED)
		$Projectiles.set_deferred(&"process_mode", Node.PROCESS_MODE_DISABLED)
		var defeat_sequence: Tween = create_tween()
		defeat_sequence.tween_interval(0.5)
		defeat_sequence.tween_callback(_fail_screen.show_failure)


func _on_fail_finished() -> void:
	run_finished.emit(false, {})


func is_finished() -> bool:
	return _finished


func _update_terrain() -> void:
	var half_extent: Vector2 = get_viewport_rect().size / (2.0 * camera.zoom.abs())
	terrain.update_around(player.global_position, half_extent)
	if enemy_spawner != null:
		enemy_spawner.update_around(player.global_position, half_extent)


func show_loadout(loadout: Dictionary[String, String]) -> bool:
	return player.apply_loadout(loadout)


func show_warmup_visuals(enabled: bool) -> void:
	_light_budget.process_mode = Node.PROCESS_MODE_ALWAYS if enabled else Node.PROCESS_MODE_INHERIT
	player.show_warmup_flash(enabled)
	_damage_vignette.modulate.a = 1.0 if enabled else 0.0
	_fail_screen.visible = enabled


func start_onboarding() -> void:
	ore_drops.guarantee_first_drop()
	_onboarding.begin(stone_map, ore_drops, ore_collector, player, enemy_spawner)


func _on_enemy_spawned(enemy: RobotEnemy) -> void:
	enemy.defeated.connect(_enemy_death_shake.trigger)


func _on_ore_spawned(ore: OreShard) -> void:
	if _finished or enemy_spawner == null or randf() >= ore_wake_chance:
		return
	var nearest: RobotEnemy
	var nearest_distance: float = INF
	var viewport_rect: Rect2 = get_viewport_rect()
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	for enemy in enemy_spawner.active_enemies():
		if not enemy.is_dormant() or not viewport_rect.has_point(canvas_transform * enemy.global_position):
			continue
		var distance: float = enemy.global_position.distance_squared_to(ore.global_position)
		if distance < nearest_distance:
			nearest = enemy
			nearest_distance = distance
	if nearest != null:
		nearest.wake_up()


func _on_projectile_entered(node: Node) -> void:
	if node is PlayerBullet:
		var bullet: PlayerBullet = node
		bullet.hit.connect(stone_map.hit)
