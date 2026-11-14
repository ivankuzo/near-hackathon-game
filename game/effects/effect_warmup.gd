extends Node2D

const ImpactFX = preload("res://enemies/robots/robot_impact_fx.gd")
const IMPACT_SCENE = preload("res://enemies/robots/robot_impact_fx.tscn")
const SENTRY_BOLT = preload("res://enemies/robots/sentry_bolt.tscn")
const BURSTS: Array[PackedScene] = [
	preload("res://world/stone/stone_chip_burst.tscn"),
	preload("res://world/stone/stone_crack_burst.tscn"),
	preload("res://world/stone/stone_break_burst.tscn"),
	preload("res://world/ore/ore_pickup_sparks.tscn"),
	preload("res://enemies/robots/robot_spark_burst.tscn"),
]
const ENEMIES: Array[PackedScene] = [
	preload("res://enemies/robots/scout.tscn"),
	preload("res://enemies/robots/sentry.tscn"),
	preload("res://enemies/robots/walker.tscn"),
]

var _projectile_sprites: Array[AnimatedSprite2D] = []


func prepare(arena: Arena) -> void:
	global_position = arena.player.global_position
	arena.stone_map.visuals.prepare_effects(self)
	for index in BURSTS.size():
		var scene: PackedScene = BURSTS[index]
		var particles: CPUParticles2D = scene.instantiate()
		add_child(particles)
		if index == 1 or index == 2:
			particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
			particles.emission_points = PackedVector2Array([Vector2.ZERO])
		particles.emitting = true
	for scene in arena.player.tool_projectiles.values():
		var bullet: PlayerBullet = scene.instantiate()
		bullet.process_mode = Node.PROCESS_MODE_DISABLED
		bullet.collision_layer = 0
		bullet.collision_mask = 0
		add_child(bullet)
		_projectile_sprites.append(bullet.get_node("Sprite2D"))
	var sentry_bolt: Node2D = SENTRY_BOLT.instantiate()
	sentry_bolt.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(sentry_bolt)
	_projectile_sprites.append(sentry_bolt.get_node("Sprite"))
	for scene in ENEMIES:
		var enemy: CharacterBody2D = scene.instantiate()
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		enemy.collision_layer = 0
		enemy.collision_mask = 0
		add_child(enemy)
	for scene in arena.ore_drops.get_ore_scenes():
		var shard: Node2D = scene.instantiate()
		shard.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(shard)
	var impact: ImpactFX = IMPACT_SCENE.instantiate()
	add_child(impact)
	impact.play_hit(impact.global_position, Vector2.RIGHT)
	impact.discharge(Vector2.RIGHT, 1.0, 1.0)


func prepare_impacts() -> void:
	for sprite in _projectile_sprites:
		if sprite.sprite_frames.has_animation(&"impact"):
			sprite.play(&"impact")


func clear() -> void:
	_projectile_sprites.clear()
	for child in get_children():
		child.free()
