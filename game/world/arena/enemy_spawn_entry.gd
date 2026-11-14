extends Resource

@export var enemy_scene: PackedScene
## Relative chance among enabled enemy types.
@export_range(0.0, 100.0, 0.1, "or_greater") var weight: float = 1.0
