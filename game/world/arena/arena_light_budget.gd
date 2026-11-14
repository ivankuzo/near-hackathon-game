extends Node

## Compatibility encodes at most 15 point lights on an individual canvas item.
@export_range(1, 15, 1) var max_lights: int = 15
@export var observer: Node2D
## These retain priority when combat creates more lights than the renderer supports.
@export var essential_lights: Array[PointLight2D] = []

var _masks: Dictionary[PointLight2D, int] = {}


func _ready() -> void:
	assert(observer != null, "ArenaLightBudget requires an observer.")
	get_tree().node_added.connect(_register)
	get_tree().node_removed.connect(_unregister)
	_register_branch(get_parent())


func _register_branch(node: Node) -> void:
	_register(node)
	for child in node.get_children():
		_register_branch(child)


func _register(node: Node) -> void:
	var light := node as PointLight2D
	if light == null or not get_parent().is_ancestor_of(light) or _masks.has(light):
		return
	_masks[light] = light.range_item_cull_mask
	light.range_item_cull_mask = 0


func _unregister(node: Node) -> void:
	var light := node as PointLight2D
	if light != null and _masks.has(light):
		light.range_item_cull_mask = _masks[light]
		_masks.erase(light)


func _process(_delta: float) -> void:
	var candidates: Array[PointLight2D] = []
	var viewport_rect: Rect2 = observer.get_viewport_rect()
	for light in _masks:
		if _masks[light] == 0 or not light.enabled or not light.is_visible_in_tree() or light.energy <= 0.001 or light.texture == null:
			continue
		var canvas_transform: Transform2D = light.get_global_transform_with_canvas()
		var center: Vector2 = canvas_transform * light.offset
		var extent: Vector2 = light.texture.get_size() * light.texture_scale * canvas_transform.get_scale().abs() * 0.5
		var radius: float = extent.length()
		if viewport_rect.intersects(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)):
			candidates.append(light)
	candidates.sort_custom(_higher_priority)
	var selected: Dictionary[PointLight2D, bool] = {}
	for index in range(mini(max_lights, candidates.size())):
		selected[candidates[index]] = true
	# Controllers keep ownership of enabled/energy; only receiver masks are budgeted here.
	for light in _masks:
		var mask: int = _masks[light] if selected.has(light) else 0
		if light.range_item_cull_mask != mask:
			light.range_item_cull_mask = mask


func _higher_priority(a: PointLight2D, b: PointLight2D) -> bool:
	var a_essential: bool = essential_lights.has(a)
	var b_essential: bool = essential_lights.has(b)
	if a_essential != b_essential:
		return a_essential
	var origin: Vector2 = observer.global_position
	var a_score: float = a.global_position.distance_squared_to(origin) / maxf(a.energy, 0.1)
	var b_score: float = b.global_position.distance_squared_to(origin) / maxf(b.energy, 0.1)
	if a_score == b_score:
		return a.get_instance_id() < b.get_instance_id()
	return a_score < b_score
