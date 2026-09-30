class_name GameConfig
extends RefCounted
## Read-only view over the JSON game config.
##
## Every gameplay number, name and colour lives in the JSON file, never in code.
## Values are addressed with dotted paths: [code]config.get_float("player.run_speed")[/code].

var _data: Dictionary


func _init(data: Dictionary = {}) -> void:
	_data = data


## Loads and parses a JSON config file. Returns an empty config on failure.
static func load_from(path: String) -> GameConfig:
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameConfig: invalid or missing JSON at %s" % path)
		return GameConfig.new()
	return GameConfig.new(parsed)


## Deep merge: keys of [param over] replace those of [param base]; nested
## dictionaries merge recursively. Neither input is modified.
## Usage: GameConfig.new(GameConfig.merged(defaults, level_def))
static func merged(base: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for key: Variant in over:
		var value: Variant = over[key]
		if value is Dictionary and out.get(key) is Dictionary:
			out[key] = merged(out[key], value)
		else:
			out[key] = value
	return out


## A view over the sub-dictionary at [param key_path] (empty config when absent).
func section(key_path: String) -> GameConfig:
	var value: Variant = get_value(key_path, {})
	return GameConfig.new(value if value is Dictionary else {})


## Returns the raw value at [param key_path], or [param default] when absent.
func get_value(key_path: String, default: Variant = null) -> Variant:
	var node: Variant = _data
	for key in key_path.split("."):
		if typeof(node) != TYPE_DICTIONARY or not (node as Dictionary).has(key):
			return default
		node = (node as Dictionary)[key]
	return node


## Returns the value at [param key_path] as a float.
func get_float(key_path: String, default: float = 0.0) -> float:
	return float(get_value(key_path, default))


## Returns the value at [param key_path] as an int.
func get_int(key_path: String, default: int = 0) -> int:
	return int(get_value(key_path, default))


## Returns the value at [param key_path] as a String.
func get_text(key_path: String, default: String = "") -> String:
	return str(get_value(key_path, default))


## Returns a 2-element JSON array as a Vector2.
func get_vec2(key_path: String, default: Vector2 = Vector2.ZERO) -> Vector2:
	var value: Variant = get_value(key_path)
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return default


## Returns a hex string ("#rrggbb") or an [r, g, b(, a)] array as a Color.
## Arrays allow values above 1.0, which brighten a sprite (hit flashes).
func get_color(key_path: String, default: Color = Color.MAGENTA) -> Color:
	var value: Variant = get_value(key_path)
	if value is String and Color.html_is_valid(value):
		return Color.html(value)
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	return default


## Returns the array at [param key_path], or an empty array.
func get_array(key_path: String) -> Array:
	var value: Variant = get_value(key_path)
	return value if value is Array else []
