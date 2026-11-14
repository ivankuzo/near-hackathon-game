extends Node2D

signal hurtbox_pose_changed(texture: Texture2D, mirrored: bool, world_center: Vector2)

const ImpactFX = preload("res://enemies/robots/robot_impact_fx.gd")

const REST: StringName = &"idle"
const RUN: StringName = &"run"
const DEATH: StringName = &"death"
const IDLE_ANIMATIONS: Array[StringName] = [REST, &"idle_damaged", &"idle_critical"]
const RUN_ANIMATIONS: Array[StringName] = [RUN, &"run_damaged", &"run_critical"]
const DEATH_EYE_ROW: int = 5
const HIT_HOLD_TIME: float = 0.04

@export_group("Animation")
@export_range(0.1, 2.0, 0.05) var run_rate: float = 1.0

@export_group("Hit Deformation")
## Maximum compression in native sprite pixels. Zero disables it.
@export_range(0.0, 6.0, 0.25, "suffix:px") var hit_depth: float = 4.0
## Width of the affected band on the armor, in native sprite pixels.
@export_range(4.0, 36.0, 1.0, "suffix:px") var hit_radius: float = 20.0
@export_range(0.04, 0.22, 0.01, "suffix:s") var hit_recovery: float = 0.12
## Local sprite Y at which deformation ends, above the feet.
@export var hit_body_bottom: float = 0.0

@export_group("Destruction")
@export_range(0.0, 10.0, 0.1, "suffix:s") var debris_rest_time: float = 2.5
@export_range(0.05, 2.0, 0.05, "suffix:s") var debris_fade_time: float = 0.45

@export_group("Electrical Damage")
## Exposed armor point relative to the left-facing idle sprite.
@export var armor_break_offset: Vector2
## Origin of the final discharge, relative to the left-facing sprite.
@export var collapse_offset: Vector2
@export_range(0.4, 1.6, 0.05) var discharge_scale: float = 1.0

@export_group("Eye")
## Eye centers relative to the sprite, starting with idle followed by the run frames.
@export var eye_offsets: PackedVector2Array
## Eye centers in the opening death frames, until the visor goes dark.
@export var death_eye_offsets: PackedVector2Array
@export_range(0.0, 2.0, 0.01) var eye_energy: float = 0.48
@export_range(1.0, 150.0, 1.0) var eye_radius: float = 46.0

@export_group("Shadow")
## Half size of the ground shadow in world pixels.
@export var shadow_half_size := Vector2(21.0, 12.0)
@export_range(0.0, 20.0, 0.5) var shadow_reach: float = 5.5

var _shadow_source: PointLight2D
var _shadow_beam: Image
var _wake_tween: Tween
var _hit_tween: Tween
var _material: ShaderMaterial
var _configured: bool = false
var _damage_stage: int = 0
var _running: bool = false
var _dying: bool = false
var _collapse_flashed: bool = false

@onready var _impact: ImpactFX = $ImpactFX
@onready var _hit_sound: AudioStreamPlayer2D = $HitSound
@onready var _damage_sound: AudioStreamPlayer2D = $DamageSound
@onready var _death_sound: AudioStreamPlayer2D = $DeathSound
@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _eye: Sprite2D = $Sprite/Eye
@onready var _light: PointLight2D = $EyeLight
@onready var _shadow: Sprite2D = $Shadow
@onready var _shadow_origin: Vector2 = _shadow.position
@onready var _shadow_base_scale: Vector2 = shadow_half_size * 2.0 / _shadow.texture.get_size()


func _ready() -> void:
	set_process(false)
	_shadow.scale = _shadow_base_scale
	var frames: SpriteFrames = _sprite.sprite_frames
	if not _has_required_animations(frames):
		_light.hide()
		_eye.hide()
		_shadow.hide()
		push_error("Robot visual requires idle, run and death animations with matching damage frames.")
		return
	if _eye.texture == null or _eye.hframes != eye_offsets.size() \
			or _eye.vframes <= DEATH_EYE_ROW or death_eye_offsets.is_empty() \
			or death_eye_offsets.size() > frames.get_frame_count(DEATH):
		_light.hide()
		_eye.hide()
		_shadow.hide()
		push_error("Robot visual requires one eye frame and center per sprite frame.")
		return
	var idle := frames.get_frame_texture(REST, 0) as AtlasTexture
	var canvas: CanvasTexture = idle.atlas as CanvasTexture if idle != null else null
	if canvas == null or canvas.diffuse_texture == null or canvas.normal_texture == null:
		push_error("Robot visual requires paired diffuse and normal atlas textures.")
		return
	_material = _sprite.material.duplicate() as ShaderMaterial
	_sprite.material = _material
	_material.set_shader_parameter(&"robot_diffuse", canvas.diffuse_texture)
	_material.set_shader_parameter(&"robot_normal", canvas.normal_texture)
	_configured = true
	_light.texture_scale = eye_radius * 2.0 / _light.texture.get_width()
	_sprite.frame_changed.connect(_sync_frame)
	_impact.flashed.connect(_set_damage_flash)
	_material.set_shader_parameter(&"damage_radius", 12.0 * discharge_scale)
	_material.set_shader_parameter(&"hit_radius", hit_radius)
	_material.set_shader_parameter(&"hit_body_bottom", hit_body_bottom)
	_sprite.play(REST)
	_sync_frame()
	set_awake(true)


func _has_required_animations(frames: SpriteFrames) -> bool:
	if frames == null or not frames.has_animation(DEATH) or frames.get_frame_count(DEATH) == 0:
		return false
	if frames.get_animation_loop_mode(DEATH) != SpriteFrames.LOOP_NONE:
		return false
	for animation in IDLE_ANIMATIONS:
		if not frames.has_animation(animation) or frames.get_frame_count(animation) != 1:
			return false
	for animation in RUN_ANIMATIONS:
		if not frames.has_animation(animation) or frames.get_frame_count(animation) + 1 != eye_offsets.size():
			return false
	return true


func is_configured() -> bool:
	return _configured


func set_motion(motion: Vector2) -> void:
	if not _configured or _dying:
		return
	if absf(motion.x) > 2.0 and _sprite.flip_h != (motion.x > 0.0):
		_sprite.flip_h = motion.x > 0.0
		_sync_frame()
	_running = motion.length_squared() > 9.0
	_play_locomotion()


func face_toward(target: Vector2) -> void:
	if not _configured or _dying or absf(target.x - global_position.x) < 12.0:
		return
	var mirrored: bool = target.x > global_position.x
	if _sprite.flip_h != mirrored:
		_sprite.flip_h = mirrored
		_sync_frame()


func play_hit(point: Vector2, outward: Vector2, health: int, maximum: int) -> void:
	_impact.play_hit(point, outward)
	_deform_armor(point, outward)
	if health > 0 and set_health(health, maximum):
		_sync_discharge_origin(_armor_offset())
		var direction := Vector2(-1.0 if _sprite.flip_h else 1.0, -0.65)
		var power: float = 1.15 if _damage_stage == 2 else 0.78
		_impact.discharge(direction, power, discharge_scale)
		_damage_sound.play()
	elif health > 0:
		_hit_sound.play()


func _deform_armor(point: Vector2, outward: Vector2) -> void:
	if hit_depth <= 0.0:
		return
	if _hit_tween != null:
		_hit_tween.kill()
	var origin: Vector2 = _sprite.to_local(point)
	var inward: Vector2 = origin.direction_to(_sprite.to_local(point - outward))
	if inward.is_zero_approx():
		inward = Vector2.DOWN
	# Physics can register contact outside the drawn armor.
	origin.x = clampf(origin.x, -hit_radius * 0.6, hit_radius * 0.6)
	origin.y = clampf(origin.y, hit_body_bottom - hit_radius * 1.6,
			hit_body_bottom - hit_radius * 0.55)
	var displacement: Vector2 = inward * hit_depth
	_material.set_shader_parameter(&"hit_origin", origin)
	_set_hit_displacement(displacement)
	_hit_tween = create_tween()
	_hit_tween.tween_interval(HIT_HOLD_TIME)
	_hit_tween.tween_method(_set_hit_displacement, displacement, Vector2.ZERO, hit_recovery) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _set_hit_displacement(displacement: Vector2) -> void:
	_material.set_shader_parameter(&"hit_displacement", displacement)


func set_health(health: int, maximum: int) -> bool:
	var stage: int = 0
	if health * 3 <= maximum:
		stage = 2
	elif health * 3 <= maximum * 2:
		stage = 1
	if stage == _damage_stage:
		return false
	var frame: int = _sprite.frame
	var progress: float = _sprite.frame_progress
	_damage_stage = stage
	_play_locomotion()
	_sprite.set_frame_and_progress(frame, progress)
	_sync_frame()
	return true


func _play_locomotion() -> void:
	var animations: Array[StringName] = RUN_ANIMATIONS if _running else IDLE_ANIMATIONS
	var animation: StringName = animations[_damage_stage]
	if _sprite.animation != animation:
		_sprite.play(animation, run_rate if _running else 1.0)
		_sync_frame()


func play_death() -> void:
	_sprite.stop()
	_dying = true
	_death_sound.play()
	# Stop waking at its current brightness so a dormant visor stays dark.
	if _wake_tween != null:
		_wake_tween.kill()
		_wake_tween = null
	_sprite.play(DEATH)
	_sync_frame()
	await _sprite.animation_finished
	var fade: Tween = create_tween()
	fade.tween_interval(debris_rest_time)
	fade.tween_property(self, ^"modulate:a", 0.0, debris_fade_time)
	await fade.finished


func set_awake(awake: bool) -> void:
	if _wake_tween != null:
		_wake_tween.kill()
		_wake_tween = null
	if _configured:
		_set_eye_power(1.0 if awake else 0.0)


func play_wake(seconds: float) -> void:
	if not _configured:
		return
	set_awake(false)
	_wake_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_wake_tween.tween_method(_set_eye_power, 0.0, 1.0, seconds * 0.18)
	_wake_tween.tween_method(_set_eye_power, 1.0, 0.08, seconds * 0.24)
	_wake_tween.tween_method(_set_eye_power, 0.08, 1.0, seconds * 0.17)
	_wake_tween.tween_method(_set_eye_power, 1.0, 0.18, seconds * 0.19)
	_wake_tween.tween_method(_set_eye_power, 0.18, 1.0, seconds * 0.22)


func _set_eye_power(power: float) -> void:
	_eye.self_modulate.a = power
	_light.enabled = power > 0.01
	_light.energy = eye_energy * power
	_material.set_shader_parameter(&"eye_power", power)


func _locomotion_column() -> int:
	return mini(_sprite.frame + 1, eye_offsets.size() - 1) if _running else 0


func _armor_offset() -> Vector2:
	return armor_break_offset + eye_offsets[_locomotion_column()] - eye_offsets[0]


func _sync_discharge_origin(offset: Vector2) -> void:
	if _sprite.flip_h:
		offset.x = -offset.x
	_impact.global_position = _sprite.to_global(offset)
	_material.set_shader_parameter(&"damage_origin", offset)


func _set_damage_flash(strength: float) -> void:
	_material.set_shader_parameter(&"damage_pulse", strength)


func publish_hurtbox_pose() -> void:
	var texture: Texture2D = _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	hurtbox_pose_changed.emit(texture, _sprite.flip_h, _sprite.global_position)


func _sync_frame() -> void:
	var column: int = _locomotion_column()
	var row: int = 1
	var offset: Vector2 = eye_offsets[column]
	if _dying:
		column = _sprite.frame
		if column >= death_eye_offsets.size():
			_set_eye_power(0.0)
			_eye.hide()
			if not _collapse_flashed:
				_collapse_flashed = true
				_sync_discharge_origin(collapse_offset)
				_impact.discharge(Vector2.UP, 1.45, discharge_scale)
			return
		row = DEATH_EYE_ROW
		offset = death_eye_offsets[column]
	_eye.frame_coords = Vector2i(column, row)
	_eye.flip_h = _sprite.flip_h
	if _sprite.flip_h:
		offset.x = -offset.x
	_light.position = _sprite.position + offset
	if not _dying:
		publish_hurtbox_pose()
		if _impact.is_discharging():
			_sync_discharge_origin(_armor_offset())


func set_shadow_light(light: PointLight2D, beam: Image) -> void:
	_shadow_source = light
	_shadow_beam = beam
	set_process(_shadow.visible and is_instance_valid(light) and beam != null)


func _process(_delta: float) -> void:
	if not is_instance_valid(_shadow_source):
		_shadow.transform = Transform2D(
			Vector2.RIGHT * _shadow_base_scale.x, Vector2.DOWN * _shadow_base_scale.y, _shadow_origin
		)
		set_process(false)
		return
	var beam_size := Vector2(_shadow_beam.get_size())
	var beam_local: Vector2 = _shadow_source.to_local(_sprite.global_position) - _shadow_source.offset
	var texel := Vector2i((beam_local / _shadow_source.texture_scale + beam_size * 0.5).floor())
	var beam_alpha: float = 0.0
	if _shadow_source.enabled and Rect2i(Vector2i.ZERO, _shadow_beam.get_size()).has_point(texel):
		beam_alpha = _shadow_beam.get_pixelv(texel).a
	var away: Vector2 = (_shadow_origin - to_local(_shadow_source.global_position)).normalized()
	var extension: float = shadow_reach * smoothstep(0.08, 0.65, beam_alpha)
	var radius: float = maxf((away * shadow_half_size).length(), 1.0)
	var stretch: Vector2 = away * (extension * 0.5 / radius)
	var x_axis: Vector2 = (Vector2.RIGHT + stretch * away.x) * _shadow_base_scale.x
	var y_axis: Vector2 = (Vector2.DOWN + stretch * away.y) * _shadow_base_scale.y
	_shadow.transform = Transform2D(x_axis, y_axis, _shadow_origin + away * extension * 0.5)
