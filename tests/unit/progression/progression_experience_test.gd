extends "res://tests/test_case.gd"
## Experience: XP curve, level-ups, overflow, cap and save round-trip.

const BASE := 100.0
const GROWTH := 2.0
const MAX_LEVEL := 4


func _exp() -> Experience:
	return Experience.new(BASE, GROWTH, MAX_LEVEL)


func test_curve_grows_by_factor_each_level() -> void:
	var e := _exp()
	assert_eq(e.xp_to_next(1), 100)
	assert_eq(e.xp_to_next(2), 200)
	assert_eq(e.xp_to_next(3), 400)


func test_xp_below_threshold_does_not_level() -> void:
	var e := _exp()
	assert_eq(e.add(99), 0)
	assert_eq(e.level, 1)
	assert_near(e.progress(), 0.99)


func test_exact_threshold_levels_up_with_zero_remainder() -> void:
	var e := _exp()
	assert_eq(e.add(100), 1)
	assert_eq(e.level, 2)
	assert_eq(e.xp, 0)


func test_big_gain_levels_several_times_and_keeps_overflow() -> void:
	var e := _exp()
	assert_eq(e.add(350), 2)
	assert_eq(e.level, 3)
	assert_eq(e.xp, 50)


func test_level_is_capped_and_progress_full() -> void:
	var e := _exp()
	e.add(100000)
	assert_eq(e.level, MAX_LEVEL)
	assert_eq(e.add(500), 0)
	assert_near(e.progress(), 1.0)


func test_state_round_trip() -> void:
	var e := _exp()
	e.add(150)
	var restored := _exp()
	restored.load_state(e.to_state())
	assert_eq(restored.level, 2)
	assert_eq(restored.xp, 50)


func test_load_state_clamps_bad_values() -> void:
	var e := _exp()
	e.load_state({"level": 99, "xp": -5})
	assert_eq(e.level, MAX_LEVEL)
	assert_eq(e.xp, 0)
