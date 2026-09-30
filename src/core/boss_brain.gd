class_name BossBrain
extends RefCounted
## Boss decision-making: which phase the boss is in and which attack comes next.
##
## Phases come from config, ordered from full health down. A phase stays active
## while the health ratio is ABOVE its [code]until_ratio[/code]; the last phase
## runs to zero. Each phase cycles through its [code]pattern[/code] of attack
## names, one every [code]interval[/code] seconds. Deterministic and testable:
## no randomness, no nodes.
##
## Transition table:
##   phase i --(ratio <= until_ratio[i])--> phase i+1   (emits "phase_change")
##   any     --(interval elapsed)---------> next attack in the phase pattern

## Index of the current phase.
var phase: int = 0

var _phases: Array[Dictionary] = []
var _timer: float = 0.0
var _step: int = 0


func _init(phases: Array = []) -> void:
	for p: Variant in phases:
		if p is Dictionary:
			_phases.append(p)
	if not _phases.is_empty():
		_timer = float(_phases[0].get("first_delay", _phases[0].get("interval", 1.0)))


## Number of configured phases.
func phase_count() -> int:
	return _phases.size()


## Config of the current phase (empty when none configured).
func current() -> Dictionary:
	return _phases[phase] if phase < _phases.size() else {}


## Phase index for a health ratio in [0, 1].
func phase_for_ratio(ratio: float) -> int:
	for i in _phases.size():
		if ratio > float(_phases[i].get("until_ratio", 0.0)):
			return i
	return maxi(0, _phases.size() - 1)


## Advances time. Returns the actions to perform now, in order:
## "phase_change" first (when the ratio crossed a threshold), then an attack name.
func tick(delta: float, health_ratio: float) -> Array[String]:
	var actions: Array[String] = []
	if _phases.is_empty():
		return actions
	var target: int = phase_for_ratio(health_ratio)
	if target > phase:
		phase = target
		_step = 0
		_timer = float(current().get("first_delay", 0.6))
		actions.append("phase_change")
	_timer -= delta
	if _timer <= 0.0:
		var pattern: Array = current().get("pattern", [])
		if not pattern.is_empty():
			actions.append(str(pattern[_step % pattern.size()]))
			_step += 1
		_timer += float(current().get("interval", 1.0))
	return actions
