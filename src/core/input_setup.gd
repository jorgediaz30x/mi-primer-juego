class_name InputSetup
extends RefCounted
## Registers the game's input actions at startup (keyboard + mouse).

const KEY_BINDINGS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_W, KEY_SPACE, KEY_UP],
	"dash": [KEY_SHIFT],
	"cast_bolt": [KEY_J],
	"cast_levitate": [KEY_K],
	"restart": [KEY_R],
	"new_game": [KEY_N],
	"cast_nova": [KEY_E],
	"cast_lumos": [KEY_F],
	"pick_1": [KEY_1],
	"pick_2": [KEY_2],
	"pick_3": [KEY_3],
	"pick_4": [KEY_4],
	"ui_back": [KEY_ESCAPE],
}

const MOUSE_BINDINGS := {
	"cast_bolt": [MOUSE_BUTTON_LEFT],
	"cast_levitate": [MOUSE_BUTTON_RIGHT],
}

## WASD layered onto Godot's BUILT-IN menu navigation actions, so title,
## options, controls and pause screens are navigable with the same keys used
## in-game. Only ADDED, never erased: [method _ensure_action] would wipe the
## engine's default arrow-key AND gamepad D-pad/stick bindings for these
## actions, breaking gamepad-only navigation.
const UI_EXTRA_KEYS := {
	"ui_up": [KEY_W],
	"ui_down": [KEY_S],
	"ui_left": [KEY_A],
	"ui_right": [KEY_D],
}


## Adds every action once. Safe to call more than once.
static func apply() -> void:
	for action: String in KEY_BINDINGS:
		_ensure_action(action)
		for keycode: Key in KEY_BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
	for action: String in MOUSE_BINDINGS:
		_ensure_action(action)
		for button: MouseButton in MOUSE_BINDINGS[action]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)
	for action: String in UI_EXTRA_KEYS:
		for keycode: Key in UI_EXTRA_KEYS[action]:
			if not _has_key_event(action, keycode):
				var event := InputEventKey.new()
				event.physical_keycode = keycode
				InputMap.action_add_event(action, event)


static func _has_key_event(action: String, keycode: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == keycode:
			return true
	return false


static func _ensure_action(action: String) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)
