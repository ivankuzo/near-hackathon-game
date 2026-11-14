class_name CameraShake
extends Node

@export var camera: Camera2D

var _noise: FastNoiseLite = FastNoiseLite.new()
var _noise_time: float = 0.0
var _rest_offset: Vector2 = Vector2.ZERO
var _amplitude: float = 0.0
var _duration: float = 0.0
var _remaining: float = 0.0
var _frequency: float = 0.0


func _ready() -> void:
	set_physics_process(false)
	if not is_instance_valid(camera):
		push_error("CameraShake needs a camera assigned in the Inspector.")
		return
	_noise.seed = randi()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	_noise.frequency = 1.0


func _physics_process(delta: float) -> void:
	if not is_instance_valid(camera):
		push_error("CameraShake lost its camera.")
		reset()
		return
	if _remaining <= delta:
		reset()
		return
	_remaining -= delta

	_noise_time += delta * _frequency
	var displacement: Vector2 = Vector2(
		_noise.get_noise_2d(_noise_time, 0.0),
		_noise.get_noise_2d(0.0, _noise_time)
	).limit_length(1.0)
	var fade: float = _remaining / _duration
	camera.offset = _rest_offset + displacement * _amplitude * fade * fade / camera.zoom


func shake(amplitude: float, duration: float, frequency: float) -> void:
	if not is_instance_valid(camera):
		push_error("CameraShake cannot shake without a valid camera.")
		return
	if (
		not is_finite(amplitude) or amplitude < 0.0
		or not is_finite(duration) or duration <= 0.0
		or not is_finite(frequency) or frequency <= 0.0
	):
		push_error("CameraShake requires a non-negative amplitude and positive duration and frequency.")
		return
	if is_zero_approx(amplitude):
		return

	if _remaining > 0.0:
		var fade: float = _remaining / _duration
		if _amplitude * fade * fade > amplitude:
			return
	else:
		_rest_offset = camera.offset
	_amplitude = amplitude
	_duration = duration
	_remaining = duration
	_frequency = frequency
	set_physics_process(true)


func reset() -> void:
	set_physics_process(false)
	if _remaining > 0.0 and is_instance_valid(camera):
		camera.offset = _rest_offset
	_remaining = 0.0


func _exit_tree() -> void:
	reset()
