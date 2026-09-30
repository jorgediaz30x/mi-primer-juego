class_name PauseMenu
extends CanvasLayer
## Esc during gameplay. Display only: [code]main.gd[/code] owns
## [code]get_tree().paused[/code] and decides what each button means.

signal resume_pressed
signal options_pressed
signal controls_pressed
## "Volver al inicio": abandon the current level and show the title screen
## again (progress up to the last checkpoint is already saved).
signal title_pressed

var _config: GameConfig


## Injects config. Call before adding to the tree.
func setup(cfg: GameConfig) -> void:
	_config = cfg


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := UiStyle.dim(0.75)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var box := UiStyle.panel(_config, Vector2(420, 410))
	box.position = Vector2(430, 150)
	add_child(box)
	var title := UiStyle.label(_config, _config.get_text("names.menu_pause_title"), "huge", "accent")
	title.position = Vector2(430, 172)
	title.size = Vector2(420, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var size := Vector2(340, 56)
	var y := 252.0
	var gap := 68.0
	var resume := UiStyle.menu_button(_config, _config.get_text("names.menu_resume"), size)
	resume.position = Vector2(470, y)
	resume.pressed.connect(func() -> void: resume_pressed.emit())
	add_child(resume)
	y += gap
	var options := UiStyle.menu_button(_config, _config.get_text("names.menu_options"), size)
	options.position = Vector2(470, y)
	options.pressed.connect(func() -> void: options_pressed.emit())
	add_child(options)
	y += gap
	var controls := UiStyle.menu_button(_config, _config.get_text("names.menu_controls"), size)
	controls.position = Vector2(470, y)
	controls.pressed.connect(func() -> void: controls_pressed.emit())
	add_child(controls)
	y += gap
	var to_title := UiStyle.menu_button(_config, _config.get_text("names.menu_to_title"), size)
	to_title.position = Vector2(470, y)
	to_title.pressed.connect(func() -> void: title_pressed.emit())
	add_child(to_title)
	hide()


func open() -> void:
	show()


func close() -> void:
	hide()
