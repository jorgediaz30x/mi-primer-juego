class_name EncounterDirector
extends RefCounted
## Scrolling-level encounters: each one triggers when the player reaches its
## [code]at_x[/code] and then spawns its groups over time (via [WaveDirector]).
##
## Pure logic: it decides WHEN an encounter starts and WHAT spawns. Positions,
## camera locks and "all enemies dead" checks belong to the level.

## Index of the running (or last finished) encounter, -1 before the first.
var index: int = -1
## True between [method try_trigger] succeeding and [method finish].
var active: bool = false

var _encounters: Array
var _waves: WaveDirector


func _init(encounters: Array = []) -> void:
	_encounters = encounters.filter(func(e: Variant) -> bool: return e is Dictionary)
	_encounters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("at_x", 0.0)) < float(b.get("at_x", 0.0)))


## Number of encounters in the level.
func count() -> int:
	return _encounters.size()


## X where the next encounter triggers, or INF when none are left.
func next_trigger_x() -> float:
	if index + 1 >= _encounters.size():
		return INF
	return float((_encounters[index + 1] as Dictionary).get("at_x", 0.0))


## Starts the next encounter if [param player_x] reached it and none is running.
## Returns the encounter's config, or an empty dictionary when nothing started.
func try_trigger(player_x: float) -> Dictionary:
	if active or player_x < next_trigger_x():
		return {}
	index += 1
	active = true
	var encounter: Dictionary = _encounters[index]
	_waves = WaveDirector.new([encounter])
	_waves.start_next_wave()
	return encounter


## Spawn events that became due in the running encounter.
func update(delta: float) -> Array[Dictionary]:
	if not active or _waves == null:
		return []
	return _waves.update(delta)


## Marks every encounter up to and including [param last_index] as done, so a
## respawn at a checkpoint does not replay them. Stops any running encounter.
func skip_through(last_index: int) -> void:
	index = clampi(last_index, -1, _encounters.size() - 1)
	active = false
	_waves = null


## x where encounter [param i] triggers (for checkpoints), or 0 when out of range.
func trigger_x_of(i: int) -> float:
	if i < 0 or i >= _encounters.size():
		return 0.0
	return float((_encounters[i] as Dictionary).get("at_x", 0.0))


## Whether the running encounter has handed out every spawn.
func all_spawned() -> bool:
	return _waves == null or _waves.all_spawned()


## Marks the running encounter as cleared.
func finish() -> void:
	active = false


## Title of the running encounter.
func current_title() -> String:
	if index < 0 or index >= _encounters.size():
		return ""
	return str((_encounters[index] as Dictionary).get("title", ""))


## Whether the running encounter locks the camera until cleared.
func current_locks_camera() -> bool:
	if index < 0 or index >= _encounters.size():
		return false
	return bool((_encounters[index] as Dictionary).get("lock", true))
