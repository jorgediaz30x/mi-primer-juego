class_name HudBar
extends Control
## Progress bar: the generated bar frame (pixel art, scaled) with a flat fill inside.
##
## Usage:
##   var bar := HudBar.new(); bar.setup(config, Vector2(300, 30), "ui.xp_fill")
##   add_child(bar); bar.set_ratio(0.4)

var _fill: ColorRect
var _inset: Vector2


## Builds the bar. [param fill_key] is the config colour of the fill.
func setup(config: GameConfig, bar_size: Vector2, fill_key: String) -> void:
	size = bar_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scale: float = config.get_float("render.pixel_scale", 3.0)
	_inset = Vector2(3, 3) * scale
	# Frame first: its centre slot is opaque art, so the fill must be drawn on top.
	var texture := SpriteHook.load_texture(config.get_text("ui.bar"))
	if texture:
		var frame := NinePatchRect.new()
		frame.texture = texture
		var margin: int = 3
		frame.patch_margin_left = margin
		frame.patch_margin_right = margin
		frame.patch_margin_top = margin
		frame.patch_margin_bottom = margin
		frame.scale = Vector2(scale, scale)
		frame.size = bar_size / scale
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(frame)
	else:
		var back := ColorRect.new()
		back.color = Color(0.02, 0.02, 0.05, 0.85)
		back.size = bar_size
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(back)
	_fill = ColorRect.new()
	_fill.color = config.get_color(fill_key, Color.WHITE)
	_fill.position = _inset
	_fill.size = bar_size - _inset * 2.0
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)


## Sets the fill, 0..1.
func set_ratio(ratio: float) -> void:
	var inner_width: float = size.x - _inset.x * 2.0
	_fill.size.x = inner_width * clampf(ratio, 0.0, 1.0)
