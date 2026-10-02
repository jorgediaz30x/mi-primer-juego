class_name WaveDirector
extends RefCounted
## Turns the wave list from config into timed spawn events.
##
## Pure timing logic: it decides WHAT spawns and WHEN. Positions are chosen by
## the level, so this class stays deterministic and testable.

var wave_index: int = -1

var _waves: Array
var _events: Array[Dictionary] = []
var _elapsed: float = 0.0


func _init(waves: Array = []) -> void:
	_waves = waves


## Number of waves in the level.
func wave_count() -> int:
	return _waves.size()


## Whether another wave is left to start.
func has_next_wave() -> bool:
	return wave_index + 1 < _waves.size()


## Starts the next wave and returns its config dictionary.
func start_next_wave() -> Dictionary:
	wave_index += 1
	_elapsed = 0.0
	_events.clear()
	var wave: Dictionary = _waves[wave_index] if _waves[wave_index] is Dictionary else {}
	for group: Variant in wave.get("groups", []):
		if group is Dictionary:
			_expand_group(group)
	_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])
	return wave


## Title of the running wave.
func current_title() -> String:
	if wave_index < 0 or wave_index >= _waves.size():
		return ""
	return str((_waves[wave_index] as Dictionary).get("title", ""))


## Advances time and returns the spawn events that became due, in order.
func update(delta: float) -> Array[Dictionary]:
	_elapsed += delta
	var due: Array[Dictionary] = []
	while not _events.is_empty() and float(_events[0]["t"]) <= _elapsed:
		due.append(_events.pop_front())
	return due


## Whether every event of the current wave has been handed out.
func all_spawned() -> bool:
	return _events.is_empty()


## Events still waiting in the current wave.
func pending_count() -> int:
	return _events.size()


func _expand_group(group: Dictionary) -> void:
	var count: int = int(group.get("count", 1))
	var interval: float = float(group.get("interval", 0.0))
	var delay: float = float(group.get("delay", 0.0))
	var side: String = str(group.get("side", "random"))
	for i in count:
		var resolved_side: String = side
		if side == "alternate":
			resolved_side = "left" if i % 2 == 0 else "right"
		_events.append({
			"t": delay + interval * i,
			"type": str(group.get("type", "spider")),
			"mode": str(group.get("mode", "side")),
			"side": resolved_side,
		})
