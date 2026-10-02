class_name TitleScreen
extends CanvasLayer
## First screen the game boots into: full-screen art, the game's name and the
## main menu. Display only: choices go out as signals, [code]main.gd[/code]
## decides what they mean (starting a run, wiping a save, quitting).
##
## "Partida nueva" asks to confirm before emitting, but only when a save
## exists — there is nothing to lose on a brand new install. "Salir" is left
## out entirely on web (there is no process to quit).

## Resume the saved run at its last checkpoint.
signal continue_pressed
## Start over: confirmed (or there was nothing to lose).
signal new_game_pressed
signal options_pressed
signal controls_pressed
signal quit_pressed
## First key/click/gamepad button on this screen. On web this is also the
## user gesture that unlocks audio playback — see [code]main.gd[/code].
signal interacted

var _config: GameConfig
var _has_save: bool = false
var _backdrop: TextureRect
var _flash: ColorRect
var _title_label: Label
var _subtitle_label: Label
var _menu_root: Control
var _continue_button: Button
var _confirm_root: Control
var _confirm_yes: Button
var _rng := RandomNumberGenerator.new()
var _pulse_t: float = 0.0
var _flash_timer: float = 0.0
var _flash_next: float = 0.0
var _interacted: bool = false


## Injects dependencies. Call before adding to the tree.
func setup(cfg: GameConfig, has_save: bool) -> void:
	_config = cfg
	_has_save = has_save


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_build_backdrop()
	_build_title()
	_build_flash()
	_build_menu()
	_build_confirm()
	_queue_next_flash()
	refresh(_has_save)


func _build_backdrop() -> void:
	_backdrop = TextureRect.new()
	_backdrop.texture = SpriteHook.load_texture(_config.get_text("ui.title.backdrop"))
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _backdrop.texture == null:
		# No art yet (generation pending/failed): a dark gray box keeps the
		# screen legible instead of showing nothing.
		var fallback := ColorRect.new()
		fallback.color = Color(0.08, 0.08, 0.1)
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fallback)
	add_child(_backdrop)
	add_child(UiStyle.dim(0.15))


func _build_title() -> void:
	_title_label = UiStyle.label(_config, _config.get_text("names.title_main"), "huge", "accent")
	_title_label.position = Vector2(0, 70)
	_title_label.size = Vector2(1280, 100)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.pivot_offset = _title_label.size * 0.5
	add_child(_title_label)
	_subtitle_label = UiStyle.label(_config, _config.get_text("names.title_subtitle"), "big")
	_subtitle_label.position = Vector2(0, 168)
	_subtitle_label.size = Vector2(1280, 60)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_subtitle_label)


func _build_flash() -> void:
	_flash = ColorRect.new()
	_flash.color = _config.get_color("ui.title.lightning_color", Color(0.75, 0.82, 1.0, 0.35))
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	add_child(_flash)


func _build_menu() -> void:
	_menu_root = Control.new()
	_menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_menu_root)
	var size := Vector2(360, 56)
	var y := 350.0
	var gap := 66.0
	_continue_button = UiStyle.menu_button(_config, _config.get_text("names.menu_continue"), size)
	_place(_continue_button, y)
	_continue_button.pressed.connect(func() -> void: continue_pressed.emit())
	_menu_root.add_child(_continue_button)
	y += gap
	var new_game := UiStyle.menu_button(_config, _config.get_text("names.menu_new_game"), size)
	_place(new_game, y)
	new_game.pressed.connect(_on_new_game_pressed)
	_menu_root.add_child(new_game)
	y += gap
	var options := UiStyle.menu_button(_config, _config.get_text("names.menu_options"), size)
	_place(options, y)
	options.pressed.connect(func() -> void: options_pressed.emit())
	_menu_root.add_child(options)
	y += gap
	var controls := UiStyle.menu_button(_config, _config.get_text("names.menu_controls"), size)
	_place(controls, y)
	controls.pressed.connect(func() -> void: controls_pressed.emit())
	_menu_root.add_child(controls)
	if not OS.has_feature("web"):
		y += gap
		var quit := UiStyle.menu_button(_config, _config.get_text("names.menu_quit"), size)
		_place(quit, y)
		quit.pressed.connect(func() -> void: quit_pressed.emit())
		_menu_root.add_child(quit)


func _build_confirm() -> void:
	_confirm_root = Control.new()
	_confirm_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_root.hide()
	add_child(_confirm_root)
	var dim := UiStyle.dim(0.75)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_root.add_child(dim)
	var title := UiStyle.label(_config, _config.get_text("names.menu_new_game_confirm_title"), "big", "danger")
	title.position = Vector2(0, 260)
	title.size = Vector2(1280, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_root.add_child(title)
	var body := UiStyle.label(_config, _config.get_text("names.menu_new_game_confirm_body"), "normal")
	body.position = Vector2(0, 320)
	body.size = Vector2(1280, 40)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_root.add_child(body)
	_confirm_yes = UiStyle.menu_button(_config, _config.get_text("names.menu_new_game_confirm_yes"), Vector2(400, 56))
	_confirm_yes.position = Vector2(440, 400)
	_confirm_yes.pressed.connect(_on_confirm_yes)
	_confirm_root.add_child(_confirm_yes)
	var cancel := UiStyle.menu_button(_config, _config.get_text("names.menu_new_game_confirm_cancel"), Vector2(400, 56))
	cancel.position = Vector2(440, 470)
	cancel.pressed.connect(_on_confirm_cancel)
	_confirm_root.add_child(cancel)


func _place(control: Control, y: float) -> void:
	control.position = Vector2((1280.0 - control.custom_minimum_size.x) * 0.5, y)


## Updates "Continuar" availability (there may not have been a save the last
## time this screen was built — e.g. returning here right after "Partida
## nueva" wiped it, or with fresh progress after "Volver al inicio").
func refresh(has_save: bool) -> void:
	_has_save = has_save
	if _continue_button:
		_continue_button.visible = has_save


func _on_new_game_pressed() -> void:
	if _has_save:
		_menu_root.hide()
		_confirm_root.show()
		_confirm_yes.grab_focus()
	else:
		new_game_pressed.emit()


func _on_confirm_yes() -> void:
	_confirm_root.hide()
	_menu_root.show()
	new_game_pressed.emit()


func _on_confirm_cancel() -> void:
	_confirm_root.hide()
	_menu_root.show()


func _process(delta: float) -> void:
	if not visible:
		return
	_pulse_t += delta
	var speed: float = _config.get_float("ui.title.pulse_speed", 1.6)
	var amount: float = _config.get_float("ui.title.pulse_amount", 0.05)
	var pulse: float = 1.0 + amount * sin(_pulse_t * speed)
	_title_label.scale = Vector2(pulse, pulse)
	_flash_timer += delta
	var flash_time: float = _config.get_float("ui.title.lightning_flash_time", 0.12)
	if _flash_timer < _flash_next:
		pass
	elif _flash_timer < _flash_next + flash_time:
		var t: float = (_flash_timer - _flash_next) / flash_time
		_flash.modulate.a = 1.0 - absf(t * 2.0 - 1.0)
	else:
		_flash.modulate.a = 0.0
		_queue_next_flash()


func _queue_next_flash() -> void:
	_flash_timer = 0.0
	_flash_next = _rng.randf_range(
		_config.get_float("ui.title.lightning_min_interval", 4.0),
		_config.get_float("ui.title.lightning_max_interval", 11.0))


func _unhandled_input(event: InputEvent) -> void:
	if _interacted or not visible:
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		if event.is_pressed():
			_interacted = true
			interacted.emit()
