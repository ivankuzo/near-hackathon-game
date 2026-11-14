class_name StoneVisuals
extends Node2D

class AnimatedStone extends Sprite2D:
	var cell: Vector2i
	var atlas_coords: Vector2i
	var alternative: int
	var occluding: bool = false
	var fade: Tween
	var accent_active: bool = false

class StoneFrame:
	var region: Rect2i
	var origin: Vector2
	var alternative: int
	var visible_height: int
	var opacity: float = 1.0

const ShaderPulse = preload("res://effects/shader_pulse/shader_pulse.gd")
const ParticleBurst = preload("res://effects/particle_burst/particle_burst.gd")
const StoneFracture = preload("res://world/stone/stone_fracture.gd")
const SILHOUETTE = preload("res://world/stone/stone_silhouette.png")
const STONE_SOURCE: int = 0

## Core silhouette relative to the observer's ground anchor, in pixels.
@export var occlusion_bounds := Rect2(-16, -64, 32, 56)
@export_range(0.0, 1.0, 0.05) var occluded_opacity: float = 0.5
@export_range(0.01, 0.5, 0.01) var fade_duration: float = 0.14
@export var crack_accent: ShaderPulse
@export var crack_chips: ParticleBurst
@export var break_chips: ParticleBurst
@export var fracture: StoneFracture

var observer: Node2D
var _animated: Dictionary[Vector2i, AnimatedStone] = {}
var _last_feet: Vector2
var _diffuse_pixels: Image
var _normal_pixels: Image
var _silhouette_pixels: Image

@onready var _tiles: TileMapLayer = $Visuals
@onready var _foreground: Node2D = $Foreground
@onready var _atlas: TileSetAtlasSource = _tiles.tile_set.get_source(STONE_SOURCE) as TileSetAtlasSource


func _process(_delta: float) -> void:
	if observer != null and _tiles.to_local(observer.global_position) != _last_feet:
		refresh_occlusion()


func set_stone(cell: Vector2i, atlas: Vector2i, alternative: int) -> void:
	if _animated.has(cell):
		_set_stone_sprite_tile(_animated[cell], cell, atlas, alternative)
	else:
		_tiles.set_cell(cell, STONE_SOURCE, atlas, alternative)


func erase_stone(cell: Vector2i) -> void:
	_tiles.erase_cell(cell)
	_remove_animated_stone(cell)


func _has_stone(cell: Vector2i) -> bool:
	return _animated.has(cell) or _tiles.get_cell_source_id(cell) != -1


func refresh_occlusion() -> void:
	if observer == null:
		return
	var feet: Vector2 = _tiles.to_local(observer.global_position)
	_last_feet = feet
	var occluding: Array[Vector2i] = []
	var size := Vector2(_tiles.tile_set.tile_size)
	var body := Rect2(feet + occlusion_bounds.position, occlusion_bounds.size)
	var feet_row: int = _tiles.local_to_map(feet).y
	var first_column: int = _tiles.local_to_map(body.position).x
	var last_column: int = _tiles.local_to_map(body.end).x
	for column in range(first_column, last_column + 1):
		var cell := Vector2i(column, feet_row + 1)
		if not _has_stone(cell):
			continue
		# The roof projects one cell north. A footprint in that cell means the robot is alongside the wall.
		var roof_cell := cell + Vector2i.UP
		if _has_stone(roof_cell):
			continue
		var roof := Rect2(_tiles.map_to_local(roof_cell) - size * 0.5, size)
		if body.intersects(roof):
			occluding.append(cell)

	for cell in _animated:
		if not occluding.has(cell):
			_fade_stone(cell, false)
	for cell in occluding:
		_fade_stone(cell, true)


func _fade_stone(cell: Vector2i, occluding: bool) -> void:
	var stone: AnimatedStone = _stone_sprite(cell)
	if stone.occluding == occluding:
		return
	if stone.fade != null:
		stone.fade.kill()

	stone.occluding = occluding
	stone.fade = stone.create_tween()
	stone.fade.tween_property(stone, ^"modulate:a", occluded_opacity if occluding else 1.0, fade_duration)
	stone.fade.finished.connect(_on_fade_finished.bind(cell))


func on_stone_cracked(cell: Vector2i) -> void:
	_play_debris(_stone_frame(cell), crack_chips, true)
	if crack_accent == null or is_zero_approx(crack_accent.strength):
		return
	var stone: AnimatedStone = _stone_sprite(cell)
	stone.accent_active = true
	crack_accent.play(stone)


func on_stone_broken(cell: Vector2i, impact_direction: Vector2) -> void:
	var frame: StoneFrame = _stone_frame(cell)
	_play_debris(frame, break_chips, false)
	if fracture != null:
		fracture.play(
			_tiles.to_global(frame.origin), _atlas.texture, frame.region,
			frame.alternative, frame.visible_height, frame.opacity, impact_direction
		)


func _stone_frame(cell: Vector2i) -> StoneFrame:
	var stone: AnimatedStone = _animated.get(cell)
	var atlas: Vector2i = stone.atlas_coords if stone != null else _tiles.get_cell_atlas_coords(cell)
	var frame := StoneFrame.new()
	frame.alternative = stone.alternative if stone != null else _tiles.get_cell_alternative_tile(cell)
	frame.region = _atlas.get_tile_texture_region(atlas)
	var tile: TileData = _atlas.get_tile_data(atlas, frame.alternative)
	frame.origin = (
		_tiles.map_to_local(cell) - Vector2(tile.texture_origin) - Vector2(frame.region.size) * 0.5
	)
	frame.visible_height = (
		_tiles.tile_set.tile_size.y if _has_stone(cell + Vector2i.DOWN) else frame.region.size.y
	)
	if stone != null:
		frame.opacity = stone.modulate.a
	return frame


func prepare_effects(target: Node2D) -> void:
	_prepare_images()
	var preview := StoneFracture.new()
	preview.contact_shadow = fracture.contact_shadow
	target.add_child(preview)
	var region: Rect2i = _atlas.get_tile_texture_region(Vector2i.ZERO)
	preview.play(target.global_position, _atlas.texture, region, 0, region.size.y, 1.0, Vector2.RIGHT)


func _prepare_images() -> void:
	if _diffuse_pixels != null:
		return
	var texture := _atlas.texture as CanvasTexture
	_diffuse_pixels = texture.diffuse_texture.get_image()
	_normal_pixels = texture.normal_texture.get_image()
	_silhouette_pixels = SILHOUETTE.get_image()


func _play_debris(frame: StoneFrame, burst: ParticleBurst, fresh_crack_only: bool) -> void:
	if burst == null:
		return
	_prepare_images()

	var region: Rect2i = frame.region
	var roof_height: int = _tiles.tile_set.tile_size.y
	var stride: int = 1 if fresh_crack_only else 3
	var previous_region: Vector2i = region.position - Vector2i(0, region.size.y)
	var points := PackedVector2Array()
	var world_origin: Vector2 = _tiles.to_global(frame.origin)
	for y in range(0, frame.visible_height, stride):
		var exposed: int = frame.alternative if y < roof_height else frame.alternative >> 2
		for x in range(0, region.size.x, stride):
			var pixel := Vector2i(x, y)
			var cut: Color = _silhouette_pixels.get_pixelv(pixel)
			if ((exposed & 1) != 0 and cut.r > 0.5) or ((exposed & 2) != 0 and cut.g > 0.5):
				continue
			if _diffuse_pixels.get_pixelv(region.position + pixel).a < 0.5:
				continue
			var depth: float = _normal_pixels.get_pixelv(region.position + pixel).a
			if fresh_crack_only:
				var previous_depth: float = _normal_pixels.get_pixelv(previous_region + pixel).a
				if depth >= previous_depth:
					continue
			var local_point: Vector2 = frame.origin + Vector2(pixel) + Vector2(0.5, 0.5)
			var point: Vector2 = _tiles.to_global(local_point) - world_origin
			points.append(point)
			if not fresh_crack_only and depth < 0.99:
				# Give the existing grooves extra weight in the breakup.
				points.append(point)
				points.append(point)
	if not points.is_empty():
		burst.play(world_origin, Vector2.RIGHT, points)


func _stone_sprite(cell: Vector2i) -> AnimatedStone:
	var stone: AnimatedStone = _animated.get(cell)
	if stone != null:
		return stone
	var atlas: Vector2i = _tiles.get_cell_atlas_coords(cell)
	var alternative: int = _tiles.get_cell_alternative_tile(cell)
	stone = AnimatedStone.new()
	stone.cell = cell
	stone.texture = _atlas.texture
	stone.region_enabled = true
	stone.z_index = _tiles.z_index - _foreground.z_index
	_set_stone_sprite_tile(stone, cell, atlas, alternative)
	_foreground.add_child(stone)
	_animated[cell] = stone
	_tiles.erase_cell(cell)
	return stone


func _set_stone_sprite_tile(
	stone: AnimatedStone, cell: Vector2i, atlas: Vector2i, alternative: int
) -> void:
	var tile: TileData = _atlas.get_tile_data(atlas, alternative)
	stone.atlas_coords = atlas
	stone.alternative = alternative
	var source_material: Material = tile.material if tile.material != null else _tiles.material
	stone.material = source_material.duplicate()
	stone.region_rect = Rect2(_atlas.get_tile_texture_region(atlas))
	# Promoted sprites sort at the same ground anchor as their original tiles.
	var sort_offset := Vector2(0, _tiles.y_sort_origin + tile.y_sort_origin)
	stone.position = _tiles.map_to_local(cell) + sort_offset
	stone.offset = -Vector2(tile.texture_origin) - sort_offset


func _on_fade_finished(cell: Vector2i) -> void:
	_animated[cell].fade = null
	_restore_stone_if_idle(cell)


func on_crack_accent_finished(target: CanvasItem) -> void:
	var stone := target as AnimatedStone
	stone.accent_active = false
	_restore_stone_if_idle(stone.cell)


func _restore_stone_if_idle(cell: Vector2i) -> void:
	var stone: AnimatedStone = _animated[cell]
	if stone.occluding or stone.fade != null or stone.accent_active:
		return
	_tiles.set_cell(cell, STONE_SOURCE, stone.atlas_coords, stone.alternative)
	_remove_animated_stone(cell)


func _remove_animated_stone(cell: Vector2i) -> void:
	var stone: AnimatedStone = _animated.get(cell)
	if stone != null:
		_animated.erase(cell)
		if stone.fade != null:
			stone.fade.kill()
		stone.hide()
		stone.queue_free()


## Materials and promoted sprites share one tiny light-position texture, updated only on movement.
func bind_light_projection(texture: Texture2D) -> void:
	var materials: Dictionary[ShaderMaterial, bool] = {}
	materials[_tiles.material as ShaderMaterial] = true
	for index in range(_atlas.get_tiles_count()):
		var coords: Vector2i = _atlas.get_tile_id(index)
		for alternative_index in range(_atlas.get_alternative_tiles_count(coords)):
			var alternative: int = _atlas.get_alternative_tile_id(coords, alternative_index)
			var tile: TileData = _atlas.get_tile_data(coords, alternative)
			if tile.material is ShaderMaterial:
				materials[tile.material as ShaderMaterial] = true
	for stone in _animated.values():
		materials[stone.material as ShaderMaterial] = true
	for shader_material in materials:
		shader_material.set_shader_parameter(&"light_projection", texture)
		shader_material.set_shader_parameter(&"projection_enabled", true)
