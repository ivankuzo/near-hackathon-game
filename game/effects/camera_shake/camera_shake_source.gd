class_name CameraShakeSource
extends Node

signal shake_requested(amplitude: float, duration: float, frequency: float)

## Maximum displacement in viewport pixels. Zero disables this source.
@export_range(0.0, 32.0, 0.1, "or_greater", "suffix:px") var amplitude: float = 3.0
## How long the impulse takes to fade out.
@export_range(0.01, 2.0, 0.01, "or_greater", "suffix:s") var duration: float = 0.12
## Noise sampling rate; higher values produce faster shake.
@export_range(1.0, 60.0, 1.0, "or_greater", "suffix:Hz") var frequency: float = 24.0


func trigger() -> void:
	shake_requested.emit(amplitude, duration, frequency)
