extends Area2D

signal collected(kind: StringName, total: int, tint: Color)

const OreShard = preload("res://world/ore/ore_shard.gd")
const ParticleBurst = preload("res://effects/particle_burst/particle_burst.gd")

@export var target: Node2D
@export var pickup_offset := Vector2(0, -58)
@export_range(0.15, 0.6, 0.01, "suffix:s") var pickup_time: float = 0.30
@export_flags_2d_physics var obstacle_mask: int = 1

var amounts: Dictionary[StringName, int] = {}
var _flash_tween: Tween
var _query := PhysicsShapeQueryParameters2D.new()

@onready var _shape: CollisionShape2D = $Shape

@onready var _sparks: ParticleBurst = $Sparks
@onready var _flash: Sprite2D = $Flash
@onready var _pickup_sound: AudioStreamPlayer = $PickupSound


func _ready() -> void:
	assert(target != null, "OreCollector requires its target assigned in the scene.")
	_query.shape = _shape.shape
	_query.collide_with_areas = true
	_query.collide_with_bodies = false
	$ScanTimer.timeout.connect(_scan)


func _scan() -> void:
	if not is_instance_valid(target):
		return
	_query.transform = _shape.global_transform
	_query.collision_mask = collision_mask
	for contact in get_world_2d().direct_space_state.intersect_shape(_query, 32):
		var area := contact["collider"] as Area2D
		var ore := area.get_parent() as OreShard
		if ore == null or not ore.can_collect():
			continue
		var ray := PhysicsRayQueryParameters2D.create(target.global_position,
				ore.global_position, obstacle_mask)
		ray.hit_from_inside = true
		if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		if ore.collect(target, pickup_offset, pickup_time):
			ore.collected.connect(_on_collected, CONNECT_ONE_SHOT)


func _on_collected(kind: StringName, tint: Color, world_point: Vector2) -> void:
	amounts[kind] = amounts.get(kind, 0) + 1
	collected.emit(kind, amounts[kind], tint)
	_pickup_sound.play()
	_sparks.play(world_point, Vector2.UP, PackedVector2Array(), 28, tint)
	if _flash_tween != null:
		_flash_tween.kill()
	_flash.global_position = world_point
	_flash.self_modulate = Color(tint, 0.9)
	_flash.scale = Vector2.ONE * 0.9
	_flash_tween = create_tween().set_parallel()
	_flash_tween.tween_property(_flash, ^"self_modulate:a", 0.0, 0.22)
	_flash_tween.tween_property(_flash, ^"scale", Vector2.ONE * 2.0, 0.22)
