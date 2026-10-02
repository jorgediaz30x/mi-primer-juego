class_name SaveStore
extends RefCounted
## Persists progression (skill points, unlocked spells, level and XP) as JSON.
##
## The path is injected so tests can write to a throwaway file.

const DEFAULT_PATH := "user://save.json"

var _path: String


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


## Reads the saved state, or an empty dictionary when there is none.
func load_state() -> Dictionary:
	if not FileAccess.file_exists(_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	return parsed if parsed is Dictionary else {}


## Writes [param state]. Returns false when the file cannot be written.
func save_state(state: Dictionary) -> bool:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveStore: cannot write %s" % _path)
		return false
	return file.store_string(JSON.stringify(state))
