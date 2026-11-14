extends Node

@export var surfaces: StoneVisuals
## The two shadow-safe player lights. Their texture offsets retain authored source positions.
@export var sources: Array[PointLight2D] = []

var _image: Image
var _texture: ImageTexture


func _ready() -> void:
	if surfaces == null or sources.size() != 2 or sources.has(null):
		push_error("StoneLightProjection requires stone surfaces and two source lights.")
		set_process(false)
		return
	_image = Image.create_empty(2, 2, false, Image.FORMAT_RGBAF)
	_image.fill(Color(0, 0, 0, 0))
	_texture = ImageTexture.create_from_image(_image)
	surfaces.bind_light_projection(_texture)


func _process(_delta: float) -> void:
	var changed: bool = false
	for index in range(2):
		var light: PointLight2D = sources[index]
		if not is_instance_valid(light):
			push_error("StoneLightProjection source was freed before its owning arena.")
			set_process(false)
			return
		var positions := Color(0, 0, 0, 0)
		var metadata := Color(0, 0, 0, 0)
		if not light.offset.is_zero_approx():
			var actual: Vector2 = light.global_position
			var authored: Vector2 = light.to_global(light.offset)
			positions = Color(actual.x, actual.y, authored.x, authored.y)
			metadata = Color(light.height, 1.0, 0, 0)
		if _image.get_pixel(index, 0) != positions or _image.get_pixel(index, 1) != metadata:
			_image.set_pixel(index, 0, positions)
			_image.set_pixel(index, 1, metadata)
			changed = true
	if changed:
		_texture.update(_image)
