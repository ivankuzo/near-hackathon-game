extends Control

signal balance_preview(value: int)
signal finished

const KINDS: Array[StringName] = [&"iron", &"copper", &"cobalt"]
const COLORS: Dictionary[StringName, Color] = {
	&"iron": Color(0.72, 0.88, 1.0),
	&"copper": Color(1.0, 0.58, 0.32),
	&"cobalt": Color(0.48, 0.7, 1.0),
}

## Screen displacement in garage pixels for each step of the payout.
@export_range(0.0, 10.0, 0.5, "suffix:px") var ore_shake: float = 1.0
@export_range(0.0, 10.0, 0.5, "suffix:px") var category_shake: float = 1.5
@export_range(0.0, 10.0, 0.5, "suffix:px") var payout_shake: float = 4.0

var _remaining: Dictionary[StringName, int] = {}
var _prices: Dictionary[StringName, int] = {}
var _previous_balance: int
var _earned: int
var _counted: int
var _balance: Control
var _balance_scale: Vector2
var _balance_pivot: Vector2
var _balance_position: Vector2
var _balance_modulate: Color
var _sequence: Tween
var _pop: Tween
var _transfer: Tween
var _focus: Tween
var _shake: Tween
var _shake_targets: Array[CanvasItem] = []
var _shake_positions: Array[Vector2] = []

@onready var _rows: Dictionary[StringName, Label] = {
	&"iron": $Panel/Iron, &"copper": $Panel/Copper, &"cobalt": $Panel/Cobalt,
}
@onready var _shards: Dictionary[StringName, Sprite2D] = {
	&"iron": $Panel/IronShard, &"copper": $Panel/CopperShard, &"cobalt": $Panel/CobaltShard,
}
@onready var _total: Label = $Panel/Total
@onready var _sparks: CPUParticles2D = $Panel/Sparks
@onready var _coin_sound: AudioStreamPlayer = $CoinSound
@onready var _payout_sound: AudioStreamPlayer = $PayoutSound
@onready var _panel: Control = $Panel
@onready var _empty_message: Label = $Panel/EmptyMessage


func play_payout(
	ore: Dictionary, prices: Dictionary[StringName, int], earned: int,
	previous_balance: int, balance: Control,
	robot: Node2D, robot_shadow: Node2D
) -> void:
	_prices.assign(prices)
	_previous_balance = previous_balance
	_shake_targets.assign([_panel, balance, robot, robot_shadow])
	_shake_positions.clear()
	for target in _shake_targets:
		_shake_positions.append(target.get("position"))
	_balance = balance
	_balance_scale = balance.scale
	_balance_pivot = balance.pivot_offset
	_balance_position = balance.position
	_balance_modulate = balance.modulate
	_earned = earned
	_counted = 0
	for kind in KINDS:
		_remaining[kind] = int(ore.get(kind, 0))
		_update_row(kind)
		_rows[kind].modulate.a = 0.35
		_shards[kind].modulate.a = 0.35
		_shards[kind].scale = Vector2.ONE
	_total.text = "+0 CREDITS"
	_empty_message.hide()
	_total.position = Vector2(90, 155)
	_total.scale = Vector2.ONE
	_total.pivot_offset = _total.size * 0.5
	show()
	grab_focus()
	_sequence = create_tween()
	_sequence.tween_interval(0.3)
	for kind in KINDS:
		_sequence.tween_callback(_focus_kind.bind(kind))
		_sequence.tween_interval(0.35)
		for _i in range(_remaining[kind]):
			_sequence.tween_callback(_count_piece.bind(kind))
			_sequence.tween_interval(0.075)
		_sequence.tween_interval(0.25)
	_sequence.tween_interval(0.3)
	_sequence.tween_callback(_start_transfer)
	_sequence.tween_interval(1.0)
	_sequence.tween_callback(_finish)


func _count_piece(kind: StringName) -> void:
	_remaining[kind] -= 1
	_counted += _prices[kind]
	_update_row(kind)
	_total.text = "+%d CREDITS" % _counted
	_total.add_theme_color_override(&"font_color", COLORS[kind])
	_sparks.color = COLORS[kind]
	_sparks.restart()
	_coin_sound.play()
	_shake_screen(ore_shake)
	_fly_shard(kind)
	if _pop != null:
		_pop.kill()
	_total.scale = Vector2(1.09, 1.09)
	_total.position = Vector2(90 + randi_range(-2, 2), 155 + randi_range(-1, 1))
	_pop = create_tween().set_parallel()
	_pop.tween_property(_total, ^"scale", Vector2.ONE, 0.1)
	_pop.tween_property(_total, ^"position", Vector2(90, 155), 0.1)


func _update_row(kind: StringName) -> void:
	_rows[kind].text = "%s  x%d" % [String(kind).to_upper(), _remaining[kind]]


func _focus_kind(kind: StringName) -> void:
	_shake_screen(category_shake)
	if _focus != null:
		_focus.kill()
	for candidate in KINDS:
		var opacity: float = 1.0 if candidate == kind else 0.35
		_rows[candidate].modulate.a = opacity
		_shards[candidate].modulate.a = opacity
		_shards[candidate].scale = Vector2.ONE
	_shards[kind].scale = Vector2.ONE * 1.25
	_focus = create_tween()
	_focus.tween_property(_shards[kind], ^"scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _fly_shard(kind: StringName) -> void:
	var shard := Sprite2D.new()
	shard.texture = _shards[kind].texture
	shard.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shard.use_parent_material = true
	shard.position = _shards[kind].position
	$Panel.add_child(shard)
	var flight: Tween = shard.create_tween().set_parallel()
	flight.tween_property(shard, ^"position", _total.position + _total.size * 0.5, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	flight.tween_property(shard, ^"scale", Vector2.ONE * 0.4, 0.22)
	flight.tween_property(shard, ^"modulate:a", 0.0, 0.1).set_delay(0.12)
	flight.chain().tween_callback(shard.queue_free)


func _start_transfer() -> void:
	if _pop != null:
		_pop.kill()
	_total.position = Vector2(90, 155)
	_total.scale = Vector2.ONE
	_total.add_theme_color_override(&"font_color", Color(1.0, 0.82, 0.42))
	if _earned == 0:
		_empty_message.modulate.a = 0.0
		_empty_message.show()
		_transfer = create_tween()
		_transfer.tween_property(_empty_message, ^"modulate:a", 1.0, 0.2)
		return
	var new_pivot := Vector2(_balance.size.x, _balance.size.y * 0.5)
	_balance.position += (_balance_scale - Vector2.ONE) * (new_pivot - _balance_pivot)
	_balance.pivot_offset = new_pivot
	_shake_positions[1] = _balance.position
	_balance.scale = _balance_scale * 1.18
	_balance.modulate = Color(1.5, 1.3, 0.7, 1.0)
	_payout_sound.play()
	_shake_screen(payout_shake)
	_transfer = create_tween().set_parallel()
	_transfer.tween_property(_balance, ^"scale", _balance_scale, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_transfer.tween_property(_balance, ^"modulate", _balance_modulate, 0.65)
	_transfer.tween_method(_show_balance, _previous_balance, _previous_balance + _earned, 0.8)


func _show_balance(value: int) -> void:
	balance_preview.emit(value)


func _shake_screen(strength: float) -> void:
	if _shake != null:
		_shake.kill()
	var side: float = 1.0 if randi_range(0, 1) == 0 else -1.0
	_apply_shake(Vector2(side * strength, strength * 0.5))
	_shake = create_tween()
	_shake.tween_method(_apply_shake, Vector2(side * strength, strength * 0.5), Vector2(-side * strength * 0.5, 0), 0.035)
	_shake.tween_method(_apply_shake, Vector2(-side * strength * 0.5, 0), Vector2.ZERO, 0.06)


func _apply_shake(offset: Vector2) -> void:
	for i in range(_shake_targets.size()):
		_shake_targets[i].set("position", (_shake_positions[i] + offset).round())


func _finish() -> void:
	if not visible:
		return
	if _sequence != null:
		_sequence.kill()
	if _pop != null:
		_pop.kill()
	if _transfer != null:
		_transfer.kill()
	if _focus != null:
		_focus.kill()
	if _shake != null:
		_shake.kill()
	_coin_sound.stop()
	_payout_sound.stop()
	_balance.scale = _balance_scale
	_balance.pivot_offset = _balance_pivot
	_balance.modulate = _balance_modulate
	_shake_positions[1] = _balance_position
	_apply_shake(Vector2.ZERO)
	balance_preview.emit(_previous_balance + _earned)
	hide()
	finished.emit()
