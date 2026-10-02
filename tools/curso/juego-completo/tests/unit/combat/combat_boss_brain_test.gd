extends "res://tests/test_case.gd"
## BossBrain: phase thresholds, pattern cycling and phase-change resets.

const PHASES := [
	{"until_ratio": 0.6, "interval": 1.0, "first_delay": 0.5, "pattern": ["volley", "teleport"]},
	{"until_ratio": 0.25, "interval": 0.5, "first_delay": 0.2, "pattern": ["summon"]},
	{"until_ratio": 0.0, "interval": 0.5, "pattern": ["rain"]},
]


func test_full_health_is_first_phase() -> void:
	assert_eq(BossBrain.new(PHASES).phase_for_ratio(1.0), 0)


func test_ratio_at_threshold_moves_to_next_phase() -> void:
	var brain := BossBrain.new(PHASES)
	assert_eq(brain.phase_for_ratio(0.6), 1)
	assert_eq(brain.phase_for_ratio(0.25), 2)
	assert_eq(brain.phase_for_ratio(0.0), 2)


func test_no_attack_before_first_delay() -> void:
	var brain := BossBrain.new(PHASES)
	assert_true(brain.tick(0.4, 1.0).is_empty())


func test_pattern_cycles_in_order() -> void:
	var brain := BossBrain.new(PHASES)
	assert_eq(brain.tick(0.5, 1.0), ["volley"])
	assert_eq(brain.tick(1.0, 1.0), ["teleport"])
	assert_eq(brain.tick(1.0, 1.0), ["volley"])


func test_phase_change_is_reported_and_resets_pattern() -> void:
	var brain := BossBrain.new(PHASES)
	brain.tick(0.5, 1.0)
	var actions := brain.tick(0.1, 0.5)
	assert_eq(actions, ["phase_change"])
	assert_eq(brain.phase, 1)
	assert_eq(brain.tick(0.2, 0.5), ["summon"])


func test_phase_never_goes_back_up() -> void:
	var brain := BossBrain.new(PHASES)
	brain.tick(0.1, 0.1)
	brain.tick(0.1, 1.0)
	assert_eq(brain.phase, 2)


func test_config_boss_has_phases_with_patterns() -> void:
	var config := GameConfig.load_from("res://assets/data/game_config.json")
	var levels := config.get_array("levels")
	var phases: Array = ((levels[levels.size() - 1] as Dictionary).get("boss", {}) as Dictionary).get("phases", [])
	assert_true(phases.size() >= 2, "boss has at least 2 phases")
	for p: Variant in phases:
		assert_true(((p as Dictionary).get("pattern", []) as Array).size() > 0, "every phase attacks")
