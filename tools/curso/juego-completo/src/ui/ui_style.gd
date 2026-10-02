class_name UiStyle
extends RefCounted
## Shared look for every screen: the pixel font, GPT Image panels and icons.
##
## Art comes from game_config.json "ui" (written by tools/art/generate_art.py);
## sizes and colours from the same block. Panels are pixel art too, so they are
## drawn at render.pixel_scale like everything else.
##
## Usage:
##   UiStyle.install_font(config)                       # once, at startup
##   var title := UiStyle.label(config, "Hola", "big")
##   var box := UiStyle.panel(config, Vector2(320, 90))


## Makes the configured font the default for every Control.
static func install_font(config: GameConfig) -> void:
	var path: String = config.get_text("ui.font")
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var font := load(path) as Font
	if font == null:
		return
	# The engine's default theme ships its own font, so the fallback alone is
	# never used: replace the default theme's font too.
	var size: int = config.get_int("ui.font_size", 24)
	ThemeDB.fallback_font = font
	ThemeDB.fallback_font_size = size
	var theme := ThemeDB.get_default_theme()
	if theme:
		theme.default_font = font
		theme.default_font_size = size


## Font size for a named step: "small", "normal", "big", "huge".
static func size_of(config: GameConfig, step: String) -> int:
	match step:
		"small":
			return config.get_int("ui.font_size_small", 18)
		"big":
			return config.get_int("ui.font_size_big", 40)
		"huge":
			return config.get_int("ui.font_size_huge", 72)
		_:
			return config.get_int("ui.font_size", 24)


## Creates an outlined label. [param color_key]: "text", "accent" or "danger".
static func label(config: GameConfig, text: String, step: String = "normal", color_key: String = "text") -> Label:
	var l := Label.new()
	l.text = text
	var size: int = size_of(config, step)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", config.get_color("ui." + color_key, Color.WHITE))
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.05, 1.0))
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", maxi(2, size / 12))
	return l


## A framed panel of [param size] screen pixels (9-slice of the generated frame,
## scaled by the pixel scale). Falls back to a dark rect without art.
static func panel(config: GameConfig, size: Vector2) -> Control:
	var texture := SpriteHook.load_texture(config.get_text("ui.panel"))
	if texture == null:
		var rect := ColorRect.new()
		rect.color = Color(0.03, 0.03, 0.07, 0.8)
		rect.size = size
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect
	var scale: float = config.get_float("render.pixel_scale", 3.0)
	var margin: int = config.get_int("ui.panel_margin", 6)
	var patch := NinePatchRect.new()
	patch.texture = texture
	patch.patch_margin_left = margin
	patch.patch_margin_right = margin
	patch.patch_margin_top = margin
	patch.patch_margin_bottom = margin
	patch.scale = Vector2(scale, scale)
	patch.size = size / scale
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return patch


## Icon [param index] from the generated icon sheets (ui_icons, then ui_icons_2,
## in the order listed in tools/art/asset_manifest.json), or null.
static func icon(config: GameConfig, index: int) -> Texture2D:
	var frames: Array = config.get_array("ui.icons.frames") + config.get_array("ui.icons_2.frames")
	if index < 0 or index >= frames.size():
		return null
	return SpriteHook.load_texture(str(frames[index]))


## Icon index for a skill-tree node or spell id (config "ui.icon_index").
static func icon_index(config: GameConfig, id: String) -> int:
	return config.get_int("ui.icon_index." + id, -1)


## Creates a full-screen dim overlay.
static func dim(alpha: float) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(0.02, 0.02, 0.05, alpha)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## A framed menu entry: a generated panel behind a flat, focusable [Button]
## that brightens on hover or keyboard/gamepad focus — real focus, unlike
## [method LevelUpScreen._add_click_area]'s mouse-only cards, so title,
## options, controls and pause menus are fully navigable without a mouse.
static func menu_button(config: GameConfig, text: String, size: Vector2, step: String = "big") -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size = size
	var box := panel(config, size)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(box)
	var caption := label(config, text, step)
	caption.set_anchors_preset(Control.PRESET_FULL_RECT)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(caption)
	var lit := func() -> void: box.modulate = Color(1.25, 1.2, 1.0)
	var unlit := func() -> void: box.modulate = Color.WHITE
	button.mouse_entered.connect(lit)
	button.mouse_exited.connect(unlit)
	button.focus_entered.connect(lit)
	button.focus_exited.connect(unlit)
	return button
