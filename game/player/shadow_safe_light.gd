extends PointLight2D

## The physical stone footprint matches its shadow occluder (layer 1).
@export_flags_2d_physics var occluder_mask: int = 1


## Call during physics, after setting the light's aim. Keep authored placement unless blocked.
func place_at(world_source: Vector2, ground_origin: Vector2) -> void:
	global_position = world_source
	offset = Vector2.ZERO
	if ground_origin.is_equal_approx(world_source):
		return
	var query := PhysicsRayQueryParameters2D.create(ground_origin, world_source, occluder_mask)
	query.hit_from_inside = true
	var contact: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if contact.is_empty():
		return
	var outward: Vector2 = contact["normal"]
	if outward.is_zero_approx():
		global_position = ground_origin
	else:
		global_position = Vector2(contact["position"]) + outward
	# Texture placement and beam aim stay fixed; only the obstructed source moves.
	offset = to_local(world_source)
