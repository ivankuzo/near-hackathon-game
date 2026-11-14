extends Node

const Catalog = preload("res://player/robot_catalog.gd")
const ModuleStats = preload("res://player/module_stats.tres")
const OrePayout = preload("res://ui/assembly/ore_payout.gd")
const GarageHint = preload("res://ui/assembly/garage_hint.gd")
const EffectWarmup = preload("res://effects/effect_warmup.gd")
const PLASMA_GUN: String = "Right_B_Welder"
const SAVE_PATH: String = "user://credits.cfg"

const SLOT_OFFSETS: Dictionary[String, Vector2] = {
	"legs": Vector2(0, 27),
	"body": Vector2.ZERO,
	"head": Vector2(0, -14),
	"left_tool": Vector2(-24, -5),
	"right_tool": Vector2(23, -5),
}
const SLOT_BOXES: Dictionary[String, Rect2] = {
	"legs": Rect2(273, 191.5, 87, 49.5),
	"body": Rect2(297, 139.5, 45.5, 34),
	"head": Rect2(305.5, 118, 27, 19),
	"left_tool": Rect2(253, 134, 34.5, 57.5),
	"right_tool": Rect2(349.5, 133, 37.5, 57.5),
}
const SLOT_TITLES: Dictionary[String, String] = {
	"legs": "CHASSIS", "body": "FRAME", "head": "HEAD",
	"left_tool": "LEFT TOOL", "right_tool": "RIGHT TOOL",
}

@export var arena_scene: PackedScene
## Player scene supplies the weapon-to-projectile mapping used in the arena.
@export var player_scene: PackedScene
## Sale price per ore shard, in credits.
@export var ore_prices: Dictionary[StringName, int] = {}
## Purchase price for each non-standard module, in credits.
@export var module_prices: Dictionary[String, int] = {}

var _loadout: Dictionary[String, String]
var _slot_buttons: Dictionary[String, Button] = {}
var _open_slot: String = ""
var _arena: Arena
var _credits: int = 150
var _onboarding_started: bool = false
var _garage_onboarding_pending: bool = false
var _owned_modules: Dictionary[String, bool] = {}
var _tool_projectiles: Dictionary[String, PackedScene] = {}
var _module_loss_tween: Tween
var _loading: bool = false

@onready var _stage: Node2D = $Stage
@onready var _assembly: Control = $Assembly
@onready var _visual: RobotVisual = $Assembly/RobotVisual
@onready var _shadow_visual: RobotVisual = $Assembly/RobotVisualShadow
@onready var _slots: Control = $Assembly/Slots
@onready var _play: Button = $Assembly/Play
@onready var _stats: RichTextLabel = $Assembly/Stats
@onready var _menu: PanelContainer = $Assembly/ModuleMenu
@onready var _menu_title: Label = $Assembly/ModuleMenu/Content/Title
@onready var _options: VBoxContainer = $Assembly/ModuleMenu/Content/Options
@onready var _menu_sound: AudioStreamPlayer = $MenuSound
@onready var _select_sound: AudioStreamPlayer = $SelectSound
@onready var _balance: RichTextLabel = $Assembly/Balance
@onready var _payout: OrePayout = $Assembly/OrePayout
@onready var _garage_hint: GarageHint = $Assembly/GarageHint
@onready var _module_loss: Label = $Assembly/ModuleLoss
@onready var _module_loss_sound: AudioStreamPlayer = $ModuleLossSound
@onready var _warmup: EffectWarmup = $WarmupLayer/Effects
@onready var _warmup_layer: CanvasLayer = $WarmupLayer
@onready var _loading_screen: CanvasLayer = $LoadingScreen


func _ready() -> void:
	if MobileControls.is_mobile():
		add_child(preload("res://ui/mobile/orientation_prompt.gd").new())
	for kind in OrePayout.KINDS:
		if not ore_prices.has(kind) or ore_prices[kind] <= 0:
			push_error("Workshop requires a positive price for ore '%s'." % kind)
			_play.disabled = true
			return
	if player_scene == null:
		push_error("Workshop requires the player scene to display weapon stats.")
		return
	var player_instance: Node = player_scene.instantiate()
	var preview_player := player_instance as Player
	if preview_player == null:
		player_instance.free()
		push_error("Workshop player scene must use the Player script.")
		return
	_tool_projectiles.assign(preview_player.tool_projectiles)
	preview_player.free()
	_loadout = Catalog.default_loadout()
	_load_progress()
	_update_balance()
	_payout.balance_preview.connect(_show_balance)
	_payout.finished.connect(_on_payout_finished)
	_update_stats()
	for slot in Catalog.slots():
		var bounds: Rect2 = SLOT_BOXES[slot]
		var button := Button.new()
		button.name = slot
		button.theme_type_variation = &"ModuleSlot"
		button.position = bounds.position
		button.size = bounds.size
		button.toggle_mode = true
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.accessibility_name = SLOT_TITLES[slot]
		button.pressed.connect(_toggle_menu.bind(slot))
		_slots.add_child(button)
		_slot_buttons[slot] = button
	_play.pressed.connect(_start_arena)
	_play.disabled = not _visual.apply_loadout(_loadout, SLOT_OFFSETS)
	if _play.disabled:
		push_error("Could not load the default robot.")
	else:
		_shadow_visual.apply_loadout(_loadout, SLOT_OFFSETS)
	if _garage_onboarding_pending:
		_show_garage_hint()
	elif not _onboarding_started and not _play.disabled:
		_loading_screen.show()
		_start_arena.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _loading:
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(_arena) and _arena.is_finished():
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel") and _menu.visible:
		_close_menu()
		get_viewport().set_input_as_handled()
	elif _menu.visible and event is InputEventMouseButton and event.pressed:
		if not _menu.get_global_rect().has_point(get_viewport().get_mouse_position()):
			_close_menu()


func _toggle_menu(slot: String) -> void:
	_menu_sound.play()
	if _open_slot == slot:
		_close_menu()
		return
	_close_menu(false)
	_open_slot = slot
	var slot_button: Button = _slot_buttons[slot]
	slot_button.set_pressed_no_signal(true)
	_menu_title.text = SLOT_TITLES[slot]
	if _garage_onboarding_pending and slot == "right_tool":
		_menu_title.text = "BUY PLASMA GUN"
	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()
	var focused: Button
	var plasma_option: Button
	for key in Catalog.variants(slot):
		var id: String = key
		var owned: bool = _is_owned(slot, id)
		var equipped: bool = id == _loadout[slot]
		if not owned and not module_prices.has(id):
			push_error("No price configured for module '%s'." % id)
			continue
		var price: int = module_prices.get(id, 0)
		var option := Button.new()
		option.use_parent_material = true
		option.theme_type_variation = &"ModuleOption"
		option.accessibility_name = _module_label(id)
		option.custom_minimum_size = Vector2(232, 28)
		option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		option.toggle_mode = true
		option.disabled = not owned and _credits < price
		option.set_pressed_no_signal(equipped)
		option.pressed.connect(_select_module.bind(slot, id))
		_options.add_child(option)
		if id == PLASMA_GUN:
			plasma_option = option
		var row := HBoxContainer.new()
		row.use_parent_material = true
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		option.add_child(row)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 8.0
		row.offset_right = -8.0
		var name_label := Label.new()
		name_label.use_parent_material = true
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.text = _module_label(id)
		name_label.modulate.a = 1.0 if owned else 0.55
		row.add_child(name_label)
		var status := Label.new()
		status.use_parent_material = true
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status.text = "EQUIPPED" if equipped else ("OWNED" if owned else "%d CR" % price)
		status.add_theme_color_override(&"font_color", Color(0.78, 0.8, 0.79) if equipped else Color(0.5, 0.53, 0.52))
		row.add_child(status)
		if option.button_pressed:
			focused = option

	_menu.reset_size()
	var menu_size: Vector2 = _menu.get_combined_minimum_size()
	var bounds: Rect2 = SLOT_BOXES[slot]
	var viewport_size: Vector2 = _assembly.size
	var x: float = bounds.end.x + 8
	if slot == "left_tool" or x + menu_size.x > viewport_size.x - 12:
		x = bounds.position.x - menu_size.x - 8
	var y: float = clampf(bounds.get_center().y - menu_size.y / 2, 56, viewport_size.y - menu_size.y - 44)
	_menu.position = Vector2(clampf(x, 12, viewport_size.x - menu_size.x - 12), y).round()
	_menu.show()
	if _garage_onboarding_pending and slot == "right_tool" and plasma_option != null:
		_show_plasma_hint.call_deferred(plasma_option)
	else:
		_garage_hint.hide()
	if focused:
		focused.grab_focus()


func _select_module(slot: String, id: String) -> void:
	var owned: bool = _is_owned(slot, id)
	if not owned and (not module_prices.has(id) or module_prices[id] < 0):
		push_error("Invalid price for module '%s'." % id)
		return
	if not owned and _credits < module_prices[id]:
		push_warning("Not enough credits for '%s'." % id)
		return
	var selection: Dictionary[String, String] = _loadout.duplicate()
	selection[slot] = id
	if not _visual.apply_loadout(selection, SLOT_OFFSETS):
		push_error("Could not fit " + _module_label(id) + ".")
		return
	_shadow_visual.apply_loadout(selection, SLOT_OFFSETS)
	if not owned:
		_credits -= module_prices[id]
		_owned_modules[id] = true
		_update_balance()
	_select_sound.play()
	_loadout = selection
	if id == PLASMA_GUN:
		_garage_onboarding_pending = false
		_garage_hint.hide()
	_save_progress()
	_update_stats()
	_close_menu()


func _update_stats() -> void:
	var stats: Vector2i = ModuleStats.totals(_loadout)
	var tool: String = _loadout["right_tool"]
	if not _tool_projectiles.has(tool):
		push_error("No projectile configured for right tool '%s'." % tool)
		return
	var instance: Node = _tool_projectiles[tool].instantiate()
	var projectile := instance as PlayerBullet
	if projectile == null:
		instance.free()
		push_error("Projectile for right tool '%s' must be a PlayerBullet." % tool)
		return
	_stats.text = (
		"[color=#97a5a1]HP[/color]  [color=#eef1ed][font_size=32]%d[/font_size][/color]"
		+ "     [color=#97a5a1]SPEED[/color]  [color=#eef1ed][font_size=32]%d[/font_size][/color]\n"
		+ "[color=#97a5a1]DMG[/color]  [color=#eef1ed][font_size=32]%d[/font_size][/color]"
		+ "     [color=#97a5a1]FIRE RATE[/color]  [color=#eef1ed][font_size=32]%.1f/s[/font_size][/color]"
	) % [stats.x, stats.y, projectile.damage, projectile.shots_per_second]
	projectile.free()


func _is_owned(slot: String, id: String) -> bool:
	return Catalog.default_loadout().get(slot, "") == id or _owned_modules.has(id)


func _close_menu(restore_focus: bool = true) -> void:
	if not _open_slot.is_empty():
		var button: Button = _slot_buttons[_open_slot]
		button.set_pressed_no_signal(false)
		if restore_focus:
			button.grab_focus()
		_open_slot = ""
	_menu.hide()
	if _garage_onboarding_pending:
		_show_garage_hint()


func _show_garage_hint() -> void:
	_garage_hint.show_target(_slot_buttons["right_tool"], "SELECT WEAPON")


func _show_plasma_hint(option: Button) -> void:
	if _garage_onboarding_pending and _open_slot == "right_tool" and is_instance_valid(option):
		_garage_hint.show_target(option, "")


func _start_arena() -> void:
	if is_instance_valid(_arena) or _loading:
		return
	_loading = true
	_loading_screen.show()
	await RenderingServer.frame_post_draw
	if _module_loss_tween != null:
		_module_loss_tween.kill()
	_module_loss.hide()
	_close_menu(false)
	_garage_hint.hide()
	var instance: Node = arena_scene.instantiate()
	if not instance is Arena:
		instance.free()
		push_error("Workshop arena scene must have the Arena script.")
		_loading = false
		_loading_screen.hide()
		return
	var arena: Arena = instance
	arena.onboarding_enabled = not _onboarding_started
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	arena.run_finished.connect(_on_run_finished, CONNECT_DEFERRED)
	_stage.add_child(arena)
	if not arena.show_loadout(_loadout):
		_stage.remove_child(arena)
		arena.queue_free()
		push_error("Could not deploy this robot.")
		_loading = false
		_loading_screen.hide()
		return
	_arena = arena
	_assembly.hide()
	_warmup.reparent(arena, false)
	_warmup.process_mode = Node.PROCESS_MODE_ALWAYS
	_warmup.prepare(arena)
	arena.show_warmup_visuals(true)
	await RenderingServer.frame_post_draw
	_warmup.prepare_impacts()
	await RenderingServer.frame_post_draw
	_warmup.clear()
	_warmup.reparent(_warmup_layer, false)
	_warmup.process_mode = Node.PROCESS_MODE_INHERIT
	arena.show_warmup_visuals(false)
	arena.process_mode = Node.PROCESS_MODE_INHERIT
	if arena.onboarding_enabled:
		arena.start_onboarding()
		_onboarding_started = true
	_save_progress()
	_select_sound.play()
	_loading = false
	_loading_screen.hide()


func _on_run_finished(won: bool, ore: Dictionary) -> void:
	if not is_instance_valid(_arena):
		return
	if _arena.onboarding_enabled and not _is_owned("right_tool", PLASMA_GUN):
		_garage_onboarding_pending = true
	_stage.remove_child(_arena)
	_arena.queue_free()
	_arena = null
	_assembly.show()
	if won:
		var earned: int = 0
		for kind in ore:
			if not ore_prices.has(kind):
				push_error("No sale price configured for ore '%s'." % kind)
				_play.grab_focus()
				return
			earned += int(ore[kind]) * ore_prices[kind]
		var previous_balance: int = _credits
		_credits += earned
		_save_progress()
		_payout.play_payout(ore, ore_prices, earned, previous_balance, _balance, _visual, _shadow_visual)
	else:
		var lost_modules: bool = false
		for slot in _loadout:
			var id: String = _loadout[slot]
			if id != Catalog.default_loadout()[slot]:
				lost_modules = true
				_owned_modules.erase(id)
		_loadout = Catalog.default_loadout()
		if not _visual.apply_loadout(_loadout, SLOT_OFFSETS):
			push_error("Could not restore the standard robot after defeat.")
			_play.disabled = true
		else:
			_shadow_visual.apply_loadout(_loadout, SLOT_OFFSETS)
			_update_stats()
		_save_progress()
		_play.grab_focus()
		if lost_modules:
			_show_module_loss()
		if _garage_onboarding_pending:
			_show_garage_hint()


func _show_module_loss() -> void:
	if _module_loss_tween != null:
		_module_loss_tween.kill()
	_module_loss.position.y = 68.0
	_module_loss.modulate.a = 0.0
	_module_loss.show()
	_module_loss_sound.play()
	_module_loss_tween = create_tween()
	_module_loss_tween.set_parallel(true)
	_module_loss_tween.tween_property(_module_loss, ^"position:y", 72.0, 0.16)
	_module_loss_tween.tween_property(_module_loss, ^"modulate:a", 1.0, 0.16)
	_module_loss_tween.chain().tween_interval(4.5)
	_module_loss_tween.chain().tween_property(_module_loss, ^"modulate:a", 0.0, 0.34)
	_module_loss_tween.chain().tween_callback(_module_loss.hide)


func _update_balance() -> void:
	_show_balance(_credits)


func _show_balance(value: int) -> void:
	_balance.text = "[right][color=#eef1ed][font_size=32]%d[/font_size][/color]  [color=#97a5a1]CREDITS[/color][/right]" % value


func _on_payout_finished() -> void:
	_play.grab_focus()
	if _garage_onboarding_pending:
		_show_garage_hint()


func _load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var config := ConfigFile.new()
	var error: Error = config.load(SAVE_PATH)
	if error != OK:
		push_error("Could not load credits: %s" % error_string(error))
		return
	_credits = int(config.get_value("player", "credits", 150))
	_onboarding_started = bool(config.get_value("player", "onboarding_started", false))
	_garage_onboarding_pending = bool(config.get_value("player", "garage_onboarding_pending", false))
	var owned: PackedStringArray = config.get_value("player", "owned_modules", PackedStringArray())
	for id in owned:
		_owned_modules[id] = true
	var saved_loadout: Dictionary = config.get_value("player", "loadout", {})
	for slot in _loadout:
		var id: String = saved_loadout.get(slot, _loadout[slot])
		if Catalog.variants(slot).has(id) and _is_owned(slot, id):
			_loadout[slot] = id


func _save_progress() -> void:
	var config := ConfigFile.new()
	if FileAccess.file_exists(SAVE_PATH):
		var load_error: Error = config.load(SAVE_PATH)
		if load_error != OK:
			push_error("Could not load saved progress: %s" % error_string(load_error))
			return
	config.set_value("player", "credits", _credits)
	config.set_value("player", "onboarding_started", _onboarding_started)
	config.set_value("player", "garage_onboarding_pending", _garage_onboarding_pending)
	config.set_value("player", "owned_modules", PackedStringArray(_owned_modules.keys()))
	config.set_value("player", "loadout", _loadout)
	var error: Error = config.save(SAVE_PATH)
	if error != OK:
		push_error("Could not save credits: %s" % error_string(error))


func _module_label(id: String) -> String:
	match id:
		"Legs_A_Standard": return "Reinforced Legs"
		"Legs_C_Light": return "Standard Legs"
		"Body_C_LightFrame": return "Standard Body"
		"Head_A_Visor": return "Visor Pro"
		"Head_B_Camera": return "Visor"
		"Right_A_Gripper": return "Pulse Gripper"
		"Right_B_Welder": return "Plasma Gun"
		"Right_C_LightRocket": return "Cannon"
		"Right_L02_NeedleDriver": return "Standard Blaster"
	return id.get_slice("_", 2).capitalize()

