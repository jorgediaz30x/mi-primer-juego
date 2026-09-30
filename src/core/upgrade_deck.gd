class_name UpgradeDeck
extends RefCounted
## Upgrades picked on level-up (1 of N random cards). They persist across deaths
## (Bloodborne-style: you die, keep what you earned, try again).
##
## Each upgrade (config "upgrades.pool") has effects as additive stat modifiers
## ("bolt.cooldown": -0.06) that STACK: taking a card twice doubles its effects,
## up to [code]max_stacks[/code]. A card may [code]require[/code] another one first,
## or a world flag ([code]requires_flag[/code], e.g. "entered_dark") so it only
## shows up when useful.
## Gameplay code asks [method get_modifier] and never knows which card gave what.
## Pure logic; randomness comes from the injected RandomNumberGenerator.

## Emitted when a card is taken, dropped or a flag is set.
signal changed

## Most upgrades owned at once (each stack counts); 0 = no limit. When full, a new
## card replaces the OLDEST one taken (a deliberate handicap: no free choice of
## what to drop) — or the player keeps what they have.
var max_owned: int = 0

var _defs: Dictionary = {}
var _order: Array[String] = []
var _stacks: Dictionary = {}
var _flags: Dictionary = {}
## One entry per stack, oldest first: the order cards were taken.
var _history: Array[String] = []


func _init(pool: Array = [], owned_limit: int = 0) -> void:
	max_owned = owned_limit
	for def: Variant in pool:
		if not def is Dictionary:
			continue
		var id: String = str((def as Dictionary).get("id", ""))
		if id.is_empty():
			continue
		_defs[id] = def
		_order.append(id)


## Config dictionary of upgrade [param id] (empty when unknown).
func get_def(id: String) -> Dictionary:
	return _defs.get(id, {})


## How many times [param id] has been taken this run.
func stacks_of(id: String) -> int:
	return int(_stacks.get(id, 0))


## Maximum times [param id] can be taken.
func max_stacks(id: String) -> int:
	return maxi(1, int(get_def(id).get("max_stacks", 1)))


## Whether [param id] can appear in an offer now (not maxed, requirement owned).
func is_eligible(id: String) -> bool:
	if not _defs.has(id) or stacks_of(id) >= max_stacks(id):
		return false
	var req: String = str(get_def(id).get("requires", ""))
	if not req.is_empty() and stacks_of(req) == 0:
		return false
	var flag: String = str(get_def(id).get("requires_flag", ""))
	return flag.is_empty() or _flags.has(flag)


## Marks a world flag (e.g. "entered_dark"); cards that require it become eligible.
func set_flag(flag: String) -> void:
	if not _flags.has(flag):
		_flags[flag] = true
		changed.emit()


## Whether [param flag] has been set.
func has_flag(flag: String) -> bool:
	return _flags.has(flag)


## Serialisable snapshot (stacks + flags).
func to_state() -> Dictionary:
	return {"stacks": _stacks.duplicate(), "flags": _flags.keys(), "history": _history.duplicate()}


## Restores a snapshot from [method to_state]. Unknown ids are dropped, stacks clamped.
func load_state(state: Dictionary) -> void:
	_stacks.clear()
	_flags.clear()
	_history.clear()
	var stacks: Variant = state.get("stacks", {})
	if stacks is Dictionary:
		for id: Variant in stacks:
			if _defs.has(str(id)):
				_stacks[str(id)] = clampi(int(stacks[id]), 0, max_stacks(str(id)))
	# Order taken: from the save, or (older saves) pool order, one entry per stack.
	var history: Variant = state.get("history", [])
	if history is Array:
		for id: Variant in history:
			if _stacks.has(str(id)) and _history.count(str(id)) < stacks_of(str(id)):
				_history.append(str(id))
	for id in _order:
		while _history.count(id) < stacks_of(id):
			_history.append(id)
	# A save from before the owned limit may hold more cards: keep the first ones.
	while max_owned > 0 and total_owned() > max_owned:
		var last: String = _history.pop_back()
		_stacks[last] = stacks_of(last) - 1
		if _stacks[last] <= 0:
			_stacks.erase(last)
	var flags: Variant = state.get("flags", [])
	if flags is Array:
		for flag: Variant in flags:
			_flags[str(flag)] = true
	changed.emit()


## Total upgrades owned (stacks count).
func total_owned() -> int:
	var total: int = 0
	for id: String in _stacks:
		total += stacks_of(id)
	return total


## Whether the owned limit is reached (a new card must replace one).
func is_full() -> bool:
	return max_owned > 0 and total_owned() >= max_owned


## Eligible cards that [param flag] unlocks (to feature them when it is raised).
func cards_unlocked_by(flag: String) -> Array[String]:
	var out: Array[String] = []
	for id in _order:
		if str(get_def(id).get("requires_flag", "")) == flag and is_eligible(id):
			out.append(id)
	return out


## Drops one stack of [param id]. Returns false when not owned.
func remove(id: String) -> bool:
	if stacks_of(id) <= 0:
		return false
	_stacks[id] = stacks_of(id) - 1
	if _stacks[id] == 0:
		_stacks.erase(id)
	_history.erase(id)
	changed.emit()
	return true


## Up to [param count] distinct eligible upgrade ids: [param featured] ones first
## (e.g. cards a new area just unlocked), then random ones.
func offer(rng: RandomNumberGenerator, count: int = 3, featured: Array[String] = []) -> Array[String]:
	var picked: Array[String] = []
	for id in featured:
		if is_eligible(id) and not id in picked and picked.size() < count:
			picked.append(id)
	var pool: Array[String] = []
	for id in _order:
		if is_eligible(id) and not id in picked:
			pool.append(id)
	# Fisher-Yates with the injected rng keeps offers reproducible in tests.
	for i in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: String = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return picked + pool.slice(0, mini(count - picked.size(), pool.size()))


## Takes upgrade [param id]. Returns false (and changes nothing) when not eligible.
func take(id: String) -> bool:
	if not is_eligible(id):
		return false
	_stacks[id] = stacks_of(id) + 1
	_history.append(id)
	changed.emit()
	return true


## The card that the next pick replaces when the deck is full ("" when none).
func oldest() -> String:
	return _history[0] if not _history.is_empty() else ""


## Drops the oldest card, then takes [param id]. Returns false when [param id]
## is not eligible (nothing changes then).
func replace_oldest_with(id: String) -> bool:
	if not _defs.has(id) or oldest().is_empty():
		return false
	var dropped: String = oldest()
	remove(dropped)
	if take(id):
		return true
	# Not eligible after all (e.g. maxed): undo the drop.
	_stacks[dropped] = stacks_of(dropped) + 1
	_history.push_front(dropped)
	changed.emit()
	return false


## Ids taken this run, in pool order.
func owned() -> Array[String]:
	var out: Array[String] = []
	for id in _order:
		if stacks_of(id) > 0:
			out.append(id)
	return out


## Sum of every taken upgrade's effect on [param stat], times its stacks.
func get_modifier(stat: String) -> float:
	var total: float = 0.0
	for id: String in _stacks:
		var effects: Variant = get_def(id).get("effects", {})
		if effects is Dictionary and (effects as Dictionary).has(stat):
			total += float(effects[stat]) * stacks_of(id)
	return total
