class_name Experience
extends RefCounted
## Player level and XP. XP needed to go from level n to n+1 is
## [code]xp_base * xp_growth^(n - 1)[/code] (config "progression").
## Pure logic: it reports level-ups; the owner decides what they grant.

## Emitted once per level gained.
signal leveled_up(new_level: int)

var level: int = 1
## XP accumulated inside the current level.
var xp: int = 0

var _base: float
var _growth: float
var _max_level: int


func _init(base: float = 100.0, growth: float = 1.35, max_level: int = 30) -> void:
	_base = base
	_growth = growth
	_max_level = max_level


## XP needed to finish level [param at_level].
func xp_to_next(at_level: int = -1) -> int:
	var n: int = level if at_level < 0 else at_level
	return maxi(1, roundi(_base * pow(_growth, n - 1)))


## Progress through the current level, 0..1 (1.0 at max level).
func progress() -> float:
	if level >= _max_level:
		return 1.0
	return clampf(float(xp) / float(xp_to_next()), 0.0, 1.0)


## Adds XP and returns how many levels were gained (can be several at once).
func add(amount: int) -> int:
	if amount <= 0 or level >= _max_level:
		return 0
	xp += amount
	var gained: int = 0
	while level < _max_level and xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		gained += 1
		leveled_up.emit(level)
	if level >= _max_level:
		xp = 0
	return gained


## Serialisable snapshot.
func to_state() -> Dictionary:
	return {"level": level, "xp": xp}


## Restores a snapshot from [method to_state]. Invalid values are clamped.
func load_state(state: Dictionary) -> void:
	level = clampi(int(state.get("level", 1)), 1, _max_level)
	xp = clampi(int(state.get("xp", 0)), 0, xp_to_next() - 1)
