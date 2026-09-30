class_name ControlsScreen
extends CanvasLayer
## Read-only list of the game's controls (config "controls.rows"). Reachable
## from the title screen and from the pause menu — one shared instance.

signal back_pressed

var _config: GameConfig
var _rows_root: Control


## Injects config. Call before adding to the tree.
func setup(cfg: GameConfig) -> void:
	_config = cfg


func _ready() -> void:
	layer = 23
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := UiStyle.dim(0.8)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var box := UiStyle.panel(_config, Vector2(900, 620))
	box.position = Vector2(190, 30)
	add_child(box)
	var title := UiStyle.label(_config, _config.get_text("names.controls_title"), "huge", "accent")
	title.position = Vector2(190, 46)
	title.size = Vector2(900, 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	# "small" + autowrap: several rows (e.g. "Lumos", "Aerum") are long enough
	# at the default font to overflow a fixed-size Label into the key column.
	_rows_root = Control.new()
	_rows_root.position = Vector2(230, 112)
	_rows_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rows_root)
	var rows: Array = _config.get_array("controls.rows")
	var row_height := 44.0
	for i in rows.size():
		var row: Dictionary = rows[i]
		var action := UiStyle.label(_config, str(row.get("action", "")), "small")
		action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		action.position = Vector2(0, i * row_height)
		action.size = Vector2(500, row_height)
		_rows_root.add_child(action)
		var key := UiStyle.label(_config, str(row.get("key", "")), "small", "accent")
		key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key.position = Vector2(520, i * row_height)
		key.size = Vector2(300, row_height)
		_rows_root.add_child(key)

	var back_button := UiStyle.menu_button(_config, _config.get_text("names.menu_back"), Vector2(280, 56))
	back_button.position = Vector2(500, 662)
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back_button)
	hide()


func open() -> void:
	show()


func close() -> void:
	hide()
