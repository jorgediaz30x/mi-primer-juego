class_name MusicMixer
extends RefCounted
## Adaptive music math: blends a calm track and a tension track from a combat
## intensity in [0, 1]. Pure logic (no audio nodes), so it is unit-testable.
##
## The target intensity comes from the game (enemy proximity, encounters); the
## mixer eases toward it (rise fast, fall slow, so danger is felt at once and
## calm returns gently) and returns equal-power gains, which keep the perceived
## loudness steady through the crossfade.

## Smoothed intensity actually heard, 0..1.
var intensity: float = 0.0

var _rise: float
var _fall: float


func _init(rise_per_second: float = 2.0, fall_per_second: float = 0.35) -> void:
	_rise = rise_per_second
	_fall = fall_per_second


## Eases [member intensity] toward [param target] over [param delta] seconds.
func update(target: float, delta: float) -> void:
	var goal: float = clampf(target, 0.0, 1.0)
	var rate: float = _rise if goal > intensity else _fall
	intensity = move_toward(intensity, goal, rate * delta)


## Linear gain of the calm track (1 at rest, 0 at full combat).
func calm_gain() -> float:
	return cos(intensity * PI * 0.5)


## Linear gain of the tension track (0 at rest, 1 at full combat).
func tension_gain() -> float:
	return sin(intensity * PI * 0.5)


## Combat intensity from the nearest enemy distance and whether a fight is on.
## [param nearest] < 0 means no enemy around.
static func target_for(nearest: float, danger_range: float, fighting: bool, fight_floor: float) -> float:
	var proximity: float = 0.0
	if nearest >= 0.0 and danger_range > 0.0:
		proximity = clampf(1.0 - nearest / danger_range, 0.0, 1.0)
	return maxf(proximity, fight_floor if fighting else 0.0)
