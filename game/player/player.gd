class_name Player
extends CharacterBody2D

signal health_changed(current: int, maximum: int)
signal damage_received

const Catalog = preload("res://player/robot_catalog.gd")
const ModularHurtbox = preload("res://player/modular_hurtbox.gd")
const ShadowSafeLight = preload("res://player/shadow_safe_light.gd")
const ModuleStats = preload("res://player/module_stats.tres")

## The level supplies a container so bullets do not follow the player.
@export var projectile_parent: Node2D
## Projectile scene for each right-tool module, configured on the player scene.
@export var tool_projectiles: Dictionary[String, PackedScene] = {}
## Headlamp beam width multiplier for each head module.
@export var headlamp_widths: Dictionary[String, float] = {}
## Headlamp color for each head module.
@export var headlamp_colors: Dictionary[String, Color] = {}

var bullet_scene: PackedScene
var max_health: int
var current_health: int
var move_speed: float
var _flash_tween: Tween
var _damage_flash_tween: Tween

@onready var _robot: RobotVisual = $RobotVisual
@onready var _projectile_hurtbox: ModularHurtbox = $ProjectileHurtbox
@onready var _fire_timer: Timer = $FireTimer
@onready var _shot_shake: CameraShakeSource = $ShotShake
@onready var _shot_sound: AudioStreamPlayer = $ShotSound
@onready var _damage_hit_sound: AudioStreamPlayer = $DamageHitSound
@onready var _shot_sound_base_pitch: float = _shot_sound.pitch_scale
@onready var _shot_sound_base_volume: float = _shot_sound.volume_db
@onready var _headlamp: ShadowSafeLight = $Headlamp
@onready var _fill_light: ShadowSafeLight = $FillLight
@onready var _fill_source_offset: Vector2 = _fill_light.position
@onready var _muzzle_flash: PointLight2D = $MuzzleFlash
@onready var _muzzle_flash_energy: float = _muzzle_flash.energy
@onready var _footprints: Dictionary[String, CollisionShape2D] = {
	"Legs_A_Standard": $StandardFootprint,
	"Legs_B_Insect": $InsectFootprint,
	"Legs_C_Light": $LightFootprint,
}


func _ready() -> void:
	_robot.hurtbox_pose_changed.connect(_projectile_hurtbox.set_pose)
	_projectile_hurtbox.damaged.connect(_take_damage)
	_muzzle_flash.energy = 0.0
	assert(projectile_parent != null, "Player needs a projectile container assigned by the level.")
	if not apply_loadout(Catalog.default_loadout()):
		set_physics_process(false)


func apply_loadout(loadout: Dictionary[String, String]) -> bool:
	var stats: Vector2i = ModuleStats.totals(loadout)
	if stats.x <= 0 or stats.y <= 0:
		push_error("Robot loadout must have positive health and movement speed.")
		return false
	var chassis: String = loadout.get("legs", "")
	var active_footprint: CollisionShape2D = _footprints.get(chassis)
	if active_footprint == null:
		push_error("No collision footprint for chassis '%s'." % chassis)
		return false
	if not _robot.apply_loadout(loadout):
		return false
	var tool: String = loadout.get("right_tool", "")
	if not tool_projectiles.has(tool):
		push_error("No projectile scene configured for right tool '%s'." % tool)
		return false
	bullet_scene = tool_projectiles[tool]
	var head: String = loadout.get("head", "")
	if not headlamp_widths.has(head):
		push_error("No headlamp width configured for head '%s'." % head)
		return false
	if not headlamp_colors.has(head):
		push_error("No headlamp color configured for head '%s'." % head)
		return false
	_headlamp.scale.y = headlamp_widths[head]
	_headlamp.color = headlamp_colors[head]
	max_health = stats.x
	current_health = max_health
	move_speed = float(stats.y)
	health_changed.emit(current_health, max_health)
	_robot.publish_hurtbox_pose()
	_headlamp.global_position = _robot.headlamp_position()
	for footprint in _footprints.values():
		footprint.set_deferred(&"disabled", footprint != active_footprint)
	return true


func _take_damage(amount: int, _point: Vector2, _outward: Vector2) -> void:
	current_health = maxi(0, current_health - amount)
	health_changed.emit(current_health, max_health)
	damage_received.emit()
	_damage_hit_sound.play()
	if _damage_flash_tween != null:
		_damage_flash_tween.kill()
	_robot.modulate = Color(1.0, 0.45, 0.45)
	_damage_flash_tween = create_tween()
	_damage_flash_tween.tween_property(_robot, ^"modulate", Color.WHITE, 0.15)


func receive_melee_hit(amount: int, direction: Vector2) -> void:
	_projectile_hurtbox.receive_damage(amount, global_position, -direction)


func show_warmup_flash(enabled: bool) -> void:
	_muzzle_flash.energy = _muzzle_flash_energy if enabled else 0.0


func scatter_on_defeat(debris_parent: Node2D) -> void:
	_projectile_hurtbox.deactivate()
	_robot.scatter_modules(debris_parent)


func _physics_process(delta: float) -> void:
	velocity = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down") * move_speed
	move_and_slide()

	var aim_position: Vector2 = get_global_mouse_position()
	var is_walking: bool = not get_real_velocity().is_zero_approx()
	_robot.set_walking(is_walking)
	_robot.advance_walk(delta)
	_robot.aim_at(aim_position)
	_robot.publish_hurtbox_pose()
	_headlamp.global_position = _robot.headlamp_position()
	if not _headlamp.global_position.is_equal_approx(aim_position):
		_headlamp.look_at(aim_position)
	_headlamp.place_at(_robot.headlamp_position(), global_position)
	_fill_light.place_at(to_global(_fill_source_offset), global_position)
	if Input.is_action_pressed(&"shoot") and _fire_timer.is_stopped():
		_fire(aim_position)


func _fire(aim_position: Vector2) -> void:
	var muzzle: Vector2 = _robot.muzzle_position()
	var direction: Vector2 = aim_position - muzzle
	if direction.is_zero_approx():
		return
	var bullet: PlayerBullet = bullet_scene.instantiate()
	if _shot_sound.stream != bullet.shot_sound:
		_shot_sound.stream = bullet.shot_sound
	_shot_sound.pitch_scale = _shot_sound_base_pitch * bullet.shot_pitch_scale
	_shot_sound.volume_db = _shot_sound_base_volume + bullet.shot_volume_offset_db
	_shot_sound.play()
	_muzzle_flash.color = bullet.light_color
	projectile_parent.add_child(bullet)
	bullet.global_transform = Transform2D(direction.angle(), muzzle)
	_fire_timer.start(1.0 / bullet.shots_per_second)
	_shot_shake.amplitude = bullet.shot_shake_amplitude
	_shot_shake.duration = bullet.shot_shake_duration
	_shot_shake.frequency = bullet.shot_shake_frequency
	_shot_shake.trigger()
	if _flash_tween != null:
		_flash_tween.kill()
	_muzzle_flash.global_position = muzzle
	_muzzle_flash.energy = _muzzle_flash_energy
	_flash_tween = create_tween()
	_flash_tween.tween_property(_muzzle_flash, ^"energy", 0.0, 0.07)
