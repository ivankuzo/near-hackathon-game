extends RefCounted

const SEARCH_PADDING: int = 5
const MAX_GOAL_OFFSET := Vector2i(12, 16)

var _stones: StoneTileMap
var _grid := AStarGrid2D.new()


func _init(stones: StoneTileMap) -> void:
	_stones = stones
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES


func find_route(origin: Vector2, destination: Vector2) -> PackedVector2Array:
	var start: Vector2i = _stones.world_to_cell(origin)
	var goal: Vector2i = _stones.world_to_cell(destination)
	goal = start + (goal - start).clamp(-MAX_GOAL_OFFSET, MAX_GOAL_OFFSET)
	var first: Vector2i = start.min(goal)
	var last: Vector2i = start.max(goal)
	_grid.region = Rect2i(first, last - first + Vector2i.ONE).grow(SEARCH_PADDING)
	_grid.update()
	for y in range(_grid.region.position.y, _grid.region.end.y):
		for x in range(_grid.region.position.x, _grid.region.end.x):
			var cell := Vector2i(x, y)
			_grid.set_point_solid(cell, cell != start and _stones.is_blocked(cell))

	var points := PackedVector2Array()
	for cell in _grid.get_id_path(start, goal, true):
		points.append(_stones.cell_center(cell))
	return points
