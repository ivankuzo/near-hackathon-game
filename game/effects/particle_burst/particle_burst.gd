extends Node2D

## One-shot scene with a CPUParticles2D root.
@export var burst_scene: PackedScene


func play(
	world_position: Vector2, world_normal: Vector2,
	points: PackedVector2Array = PackedVector2Array(), amount: int = 0,
	tint: Color = Color.WHITE
) -> void:
	var particles: CPUParticles2D = burst_scene.instantiate()
	if amount > 0:
		particles.amount = amount
	particles.modulate = tint
	add_child(particles)
	particles.global_position = world_position
	particles.global_rotation = world_normal.angle()
	if not points.is_empty():
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
		particles.emission_points = points
	particles.finished.connect(particles.queue_free, CONNECT_ONE_SHOT)
	particles.emitting = true
