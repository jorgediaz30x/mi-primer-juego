class_name OptionsScreen
extends CanvasLayer
## Volume and display options. Display only: every change goes out as a
## signal; [Settings] (via [code]main.gd[/code]) decides how to clamp and
## apply it. Reachable from the title screen and from the pause menu — this
## single instance is shared by both, so it never gets out of sync with them.

signal master_volume_changed(volume: float)
signal music_volume_changed(volume: float)
signal sfx_volume_changed(volume: float)
signal fullscreen_toggled(on: bool)
signal back_pressed

var _config: GameConfig
var _master_slider: HSlider
var _music_slider: HSlider
var _sfx_slider: HSlider
var _master_pct: Label
var _music_pct: Label
var _sfx_pct: Label
var _fullscreen_toggle: CheckButton
var _back_button: Button


## Injects config. Call before adding to the tree.
func setup(cfg: GameConfig) -> void:
	_config = cfg


func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := UiStyle.dim(0.8)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var box := UiStyle.panel(_config, Vector2(620, 460))
	box.position = Vector2(330, 120)
	add_child(box)
	var title := UiStyle.label(_config, _config.get_text("names.options_title"), "huge", "accent")
	title.position = Vector2(330, 144)
	title.size = Vector2(620, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var y := 250.0
	_master_slider = _build_slider_label(_config.get_text("names.options_master"), y)
	_master_pct = _build_pct_label(y)
	_master_slider.value_changed.connect(_on_master_changed)
	y += 84.0
	_music_slider = _build_slider_label(_config.get_text("names.options_music"), y)
	_music_pct = _build_pct_label(y)
	_music_slider.value_changed.connect(_on_music_changed)
	y += 84.0
	_sfx_slider = _build_slider_label(_config.get_text("names.options_sfx"), y)
	_sfx_pct = _build_pct_label(y)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	y += 84.0

	var fs_label := UiStyle.label(_config, _config.get_text("names.options_fullscreen"))
	fs_label.position = Vector2(390, y + 8)
	fs_label.size = Vector2(300, 34)
	add_child(fs_label)
	_fullscreen_toggle = CheckButton.new()
	_fullscreen_toggle.position = Vector2(760, y)
	_fullscreen_toggle.toggled.connect(func(on: bool) -> void: fullscreen_toggled.emit(on))
	add_child(_fullscreen_toggle)

	_back_button = UiStyle.menu_button(_config, _config.get_text("names.menu_back"), Vector2(280, 56))
	_back_button.position = Vector2(500, 630)
	_back_button.pressed.connect(func() -> void: back_pressed.emit())
	add_child(_back_button)
	hide()


## Builds one row's caption + slider, returning the slider (the row's
## percentage readout is built separately by [method _build_pct_label]).
func _build_slider_label(text: String, y: float) -> HSlider:
	var caption := UiStyle.label(_config, text)
	caption.position = Vector2(390, y)
	caption.size = Vector2(220, 34)
	add_child(caption)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.position = Vector2(390, y + 36)
	slider.size = Vector2(380, 24)
	add_child(slider)
	return slider


func _build_pct_label(y: float) -> Label:
	var pct := UiStyle.label(_config, "100%", "small", "accent")
	pct.position = Vector2(780, y + 30)
	pct.size = Vector2(80, 30)
	add_child(pct)
	return pct


## Shows the screen with its sliders set from [param settings]'s current
## values (it may have changed since this screen was last open).
func open(settings: Settings) -> void:
	_master_slider.set_value_no_signal(roundi(settings.master_volume * 100.0))
	_master_pct.text = "%d%%" % roundi(settings.master_volume * 100.0)
	_music_slider.set_value_no_signal(roundi(settings.music_volume * 100.0))
	_music_pct.text = "%d%%" % roundi(settings.music_volume * 100.0)
	_sfx_slider.set_value_no_signal(roundi(settings.sfx_volume * 100.0))
	_sfx_pct.text = "%d%%" % roundi(settings.sfx_volume * 100.0)
	_fullscreen_toggle.set_pressed_no_signal(settings.fullscreen)
	show()
	_master_slider.grab_focus()


func close() -> void:
	hide()


func _on_master_changed(value: float) -> void:
	_master_pct.text = "%d%%" % int(value)
	master_volume_changed.emit(value / 100.0)


func _on_music_changed(value: float) -> void:
	_music_pct.text = "%d%%" % int(value)
	music_volume_changed.emit(value / 100.0)


func _on_sfx_changed(value: float) -> void:
	_sfx_pct.text = "%d%%" % int(value)
	sfx_volume_changed.emit(value / 100.0)
