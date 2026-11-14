extends Node2D

signal flashed(strength: float)

const ParticleBurst = preload("res://effects/particle_burst/particle_burst.gd")
const ARC_RESHAPE_INTERVAL: float = 0.052

@export var flash_curve: Curve
@export_range(0.1, 0.6, 0.01, "suffix:s") var discharge_time: float = 0.28
@export_range(4.0, 50.0, 1.0, "suffix:px") var arc_reach: float = 19.0
@export_range(1, 24, 1) var hit_sparks: int = 11
@export_range(0.05, 0.5, 0.01, "suffix:s") var spark_flash_time: float = 0.18
@export_range(1, 48, 1) var discharge_sparks: int = 29
@export var arc_color := Color("#5b9fef")
@export var core_color := Color("#dcffff")

var _age: float = 0.0
var _duration: float = 0.0
var _power: float = 0.0
var _reach: float = 0.0
var _brightness: float = 0.0
var _last_shape: int = -1
var _pixels: Dictionary[Vector2i, bool] = {}
var _spark_flash_tween: Tween

@onready var _sparks: ParticleBurst = $Sparks
@onready var _spark_light: PointLight2D = $SparkFlash
@onready var _spark_light_energy: float = _spark_light.energy
@onready var _light: PointLight2D = $Flash
@onready var _light_energy: float = _light.energy
@onready var _light_scale: float = _light.texture_scale


func _ready() -> void:
	set_process(false)


func play_hit(point: Vector2, outward: Vector2) -> void:
	_sparks.play(point, outward, PackedVector2Array(), hit_sparks)
	if _spark_flash_tween != null:
		_spark_flash_tween.kill()
	_spark_light.global_position = point
	_spark_light.energy = _spark_light_energy
	_spark_light.show()
	_spark_flash_tween = create_tween()
	_spark_flash_tween.tween_property(_spark_light, ^"energy", 0.0, spark_flash_time)
	_spark_flash_tween.tween_callback(_spark_light.hide)


func discharge(outward: Vector2, power: float, size_scale: float) -> void:
	_age = 0.0
	_power = power
	_duration = discharge_time * sqrt(power)
	_reach = arc_reach * size_scale * power
	_last_shape = -1
	_light.texture_scale = _light_scale * size_scale * sqrt(power)
	var count: int = roundi(discharge_sparks * power)
	_sparks.play(global_position, outward, PackedVector2Array(), count)
	_update_flash()
	set_process(true)


func is_discharging() -> bool:
	return is_processing()


func _process(delta: float) -> void:
	_age += delta
	if _age >= _duration:
		_brightness = 0.0
		_light.enabled = false
		flashed.emit(0.0)
		queue_redraw()
		set_process(false)
		return
	_update_flash()


func _update_flash() -> void:
	var progress: float = _age / _duration
	_brightness = flash_curve.sample_baked(progress)
	_light.energy = _light_energy * _brightness * _power
	_light.enabled = _brightness > 0.025
	flashed.emit(_brightness * _power)
	var shape_index: int = floori(_age / ARC_RESHAPE_INTERVAL)
	if shape_index != _last_shape:
		_last_shape = shape_index
		_build_arcs(_reach * lerpf(1.0, 0.46, progress))
	queue_redraw()


func _build_arcs(reach: float) -> void:
	_pixels.clear()
	var phase: float = randf_range(0.0, TAU)
	var arc_count: int = 4 if _power > 1.0 else 3
	for index in range(arc_count):
		var axis := Vector2.from_angle(phase + TAU * index / arc_count + randf_range(-0.35, 0.35))
		var across: Vector2 = axis.orthogonal()
		var length: float = reach * randf_range(0.60, 1.0)
		var offset: float = length * randf_range(0.11, 0.25)
		var knee: Vector2 = axis * length * 0.32 + across * offset
		var elbow: Vector2 = axis * length * 0.63 - across * offset * 0.65
		_stamp(Vector2.ZERO, knee, true)
		_stamp(knee, elbow, true)
		_stamp(elbow, axis * length, false)
		_stamp(knee, knee + (axis + across) * length * 0.31, false)


func _stamp(start: Vector2, end: Vector2, core: bool) -> void:
	for pixel in Geometry2D.bresenham_line(Vector2i(start.round()), Vector2i(end.round())):
		_pixels[pixel] = core or _pixels.get(pixel, false)


func _draw() -> void:
	if _brightness <= 0.0:
		return
	var fringe := Color(arc_color, _brightness * 0.82)
	var core := Color(core_color, _brightness)
	for pixel in _pixels:
		draw_rect(Rect2(Vector2(pixel), Vector2.ONE), core if _pixels[pixel] else fringe)
	if _brightness > 0.7:
		draw_rect(Rect2(-1.0, -1.0, 3.0, 3.0), core)
