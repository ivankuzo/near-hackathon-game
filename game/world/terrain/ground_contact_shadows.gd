extends Node2D

## Distance the contact darkening extends outside a block's ground footprint.
@export_range(1.0, 16.0, 0.5, "suffix:px") var shadow_width: float = 6.0
@export_range(0.0, 0.6, 0.01) var shadow_strength: float = 0.55
@export var edge_texture: Texture2D
@export var corner_texture: Texture2D

var _cells: Dictionary[Vector2i, Rect2] = {}


func update_cells(blocks: TileMapLayer, changed: Array[Vector2i]) -> void:
	var size := Vector2(blocks.tile_set.tile_size)
	for cell in changed:
		if blocks.get_cell_source_id(cell) == -1:
			_cells.erase(cell)
		else:
			var center: Vector2 = to_local(blocks.to_global(blocks.map_to_local(cell)))
			_cells[cell] = Rect2(center - size * 0.5, size)
	queue_redraw()


func _draw() -> void:
	var tint := Color(0.0, 0.0, 0.0, shadow_strength)
	for cell in _cells:
		var bounds: Rect2 = _cells[cell]
		var top: bool = not _cells.has(cell + Vector2i.UP)
		var bottom: bool = not _cells.has(cell + Vector2i.DOWN)
		var left: bool = not _cells.has(cell + Vector2i.LEFT)
		var right: bool = not _cells.has(cell + Vector2i.RIGHT)
		if top:
			_draw_edge(bounds.position, -PI * 0.5, bounds.size.x, tint)
		if bottom:
			_draw_edge(bounds.end, PI * 0.5, bounds.size.x, tint)
		if left:
			_draw_edge(Vector2(bounds.position.x, bounds.end.y), PI, bounds.size.y, tint)
		if right:
			_draw_edge(Vector2(bounds.end.x, bounds.position.y), 0.0, bounds.size.y, tint)
		draw_set_transform(Vector2.ZERO)
		if top and left:
			_draw_corner(bounds.position, Vector2(-1.0, -1.0), tint)
		if top and right:
			_draw_corner(Vector2(bounds.end.x, bounds.position.y), Vector2(0.0, -1.0), tint)
		if bottom and left:
			_draw_corner(Vector2(bounds.position.x, bounds.end.y), Vector2(-1.0, 0.0), tint)
		if bottom and right:
			_draw_corner(bounds.end, Vector2.ZERO, tint)


func _draw_edge(origin: Vector2, angle: float, length: float, tint: Color) -> void:
	draw_set_transform(origin, angle)
	draw_texture_rect(edge_texture, Rect2(0.0, 0.0, shadow_width, length), false, tint)


func _draw_corner(origin: Vector2, quadrant: Vector2, tint: Color) -> void:
	var half_size: Vector2 = corner_texture.get_size() * 0.5
	var destination := Rect2(origin + quadrant * shadow_width, Vector2.ONE * shadow_width)
	var source := Rect2((quadrant + Vector2.ONE) * half_size, half_size)
	draw_texture_rect_region(corner_texture, destination, source, tint)
