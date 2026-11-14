extends Resource

## Convex shapes in centered sprite coordinates, keyed by atlas frame origin.
@export var polygons_by_frame: Dictionary[Vector2i, Array] = {}

var _shape_cache: Dictionary[Vector3i, Array] = {}


func shapes_for(frame: Vector2i, mirrored: bool) -> Array[Shape2D]:
	var key := Vector3i(frame.x, frame.y, int(mirrored))
	if _shape_cache.has(key):
		return _shape_cache[key]

	var shapes: Array[Shape2D] = []
	for points: PackedVector2Array in polygons_by_frame.get(frame, []):
		var polygon: PackedVector2Array = points.duplicate()
		if mirrored:
			for index in range(polygon.size()):
				var point: Vector2 = polygon[index]
				polygon[index] = Vector2(-point.x, point.y)
			polygon.reverse()
		var shape := ConvexPolygonShape2D.new()
		shape.points = polygon
		shapes.append(shape)
	_shape_cache[key] = shapes
	return shapes
