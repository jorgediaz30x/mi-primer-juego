class_name ComboCounter
extends RefCounted
## Kill-chain multiplier: every kill inside the time window raises the multiplier.

var count: int = 0

var _window: float
var _step: float
var _max_multiplier: float
var _timer: float = 0.0


func _init(window: float = 1.5, step_per_kill: float = 0.25, max_multiplier: float = 3.0) -> void:
	_window = window
	_step = step_per_kill
	_max_multiplier = max_multiplier


## Registers a kill, restarts the window and returns the new multiplier.
func register_kill() -> float:
	count += 1
	_timer = _window
	return multiplier()


## Current multiplier: 1.0 for the first kill, +step for each chained one, capped.
func multiplier() -> float:
	return minf(1.0 + _step * maxi(count - 1, 0), _max_multiplier)


## Fraction of the window left (1.0 = just killed, 0.0 = chain broken).
func time_left_ratio() -> float:
	return clampf(_timer / _window, 0.0, 1.0) if _window > 0.0 else 0.0


## Advances time; the chain breaks when the window runs out.
func tick(delta: float) -> void:
	if count == 0:
		return
	_timer -= delta
	if _timer <= 0.0:
		count = 0
		_timer = 0.0
