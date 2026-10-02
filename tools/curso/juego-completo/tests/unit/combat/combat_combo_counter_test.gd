extends "res://tests/test_case.gd"
## ComboCounter: multiplier growth, cap and window expiry.

const WINDOW := 1.5
const STEP := 0.25
const CAP := 2.0


func test_first_kill_multiplier_is_one() -> void:
	var combo := ComboCounter.new(WINDOW, STEP, CAP)
	assert_near(combo.register_kill(), 1.0)


func test_chained_kills_raise_multiplier_by_step() -> void:
	var combo := ComboCounter.new(WINDOW, STEP, CAP)
	combo.register_kill()
	combo.register_kill()
	assert_near(combo.register_kill(), 1.5)


func test_multiplier_is_capped() -> void:
	var combo := ComboCounter.new(WINDOW, STEP, CAP)
	for i in 20:
		combo.register_kill()
	assert_near(combo.multiplier(), CAP)


func test_chain_breaks_after_window() -> void:
	var combo := ComboCounter.new(WINDOW, STEP, CAP)
	combo.register_kill()
	combo.register_kill()
	combo.tick(WINDOW + 0.01)
	assert_eq(combo.count, 0)
	assert_near(combo.register_kill(), 1.0)


func test_kill_inside_window_keeps_chain() -> void:
	var combo := ComboCounter.new(WINDOW, STEP, CAP)
	combo.register_kill()
	combo.tick(WINDOW * 0.5)
	combo.register_kill()
	assert_eq(combo.count, 2)
