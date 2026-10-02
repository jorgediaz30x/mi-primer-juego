extends "res://tests/test_case.gd"
## EncounterDirector: x-triggered encounters, ordering and completion.

const ENCOUNTERS := [
	{"at_x": 2000, "title": "second", "lock": false, "groups": [
		{"type": "spider", "mode": "ceiling", "count": 1, "interval": 0.0, "delay": 0.0}]},
	{"at_x": 500, "title": "first", "groups": [
		{"type": "spider", "mode": "side", "side": "left", "count": 2, "interval": 1.0, "delay": 0.0}]},
]


func test_nothing_triggers_before_first_x() -> void:
	var director := EncounterDirector.new(ENCOUNTERS)
	assert_true(director.try_trigger(499.0).is_empty())
	assert_false(director.active)


func test_encounters_are_sorted_by_x() -> void:
	var director := EncounterDirector.new(ENCOUNTERS)
	assert_eq(str(director.try_trigger(600.0).get("title")), "first")


func test_second_encounter_waits_until_first_finishes() -> void:
	var director := EncounterDirector.new(ENCOUNTERS)
	director.try_trigger(600.0)
	assert_true(director.try_trigger(5000.0).is_empty(), "blocked while active")
	director.finish()
	assert_eq(str(director.try_trigger(5000.0).get("title")), "second")


func test_running_encounter_releases_its_spawns() -> void:
	var director := EncounterDirector.new(ENCOUNTERS)
	director.try_trigger(600.0)
	assert_eq(director.update(0.0).size(), 1)
	assert_false(director.all_spawned())
	assert_eq(director.update(1.5).size(), 1)
	assert_true(director.all_spawned())


func test_lock_defaults_true_and_reads_config() -> void:
	var director := EncounterDirector.new(ENCOUNTERS)
	director.try_trigger(600.0)
	assert_true(director.current_locks_camera())
	director.finish()
	director.try_trigger(2500.0)
	assert_false(director.current_locks_camera())


func test_next_trigger_is_inf_when_done() -> void:
	var director := EncounterDirector.new(ENCOUNTERS)
	director.try_trigger(600.0)
	director.finish()
	director.try_trigger(2500.0)
	director.finish()
	assert_eq(director.next_trigger_x(), INF)


func test_every_level_has_well_formed_encounters_inside_its_length() -> void:
	var config := GameConfig.load_from("res://assets/data/game_config.json")
	for level: Variant in config.get_array("levels"):
		var def: Dictionary = level
		var director := EncounterDirector.new(def.get("encounters", []))
		assert_true(director.count() > 0, "%s has encounters" % def.get("id"))
		var x: float = 0.0
		while director.next_trigger_x() != INF:
			x = director.next_trigger_x()
			director.try_trigger(x)
			assert_true(director.update(999.0).size() > 0, "%s encounter %d spawns" % [def.get("id"), director.index])
			director.finish()
		# Boss levels: the arena is the last screen, encounters must come before it.
		# Other levels: encounters must come before the exit at the right edge.
		var length: float = float(def.get("fallback_length", 0))
		var limit: float = length - 1280.0 if def.get("boss") is Dictionary else length - 400.0
		assert_true(x < limit, "%s last encounter (x=%d) before %d" % [def.get("id"), x, limit])


func test_skip_through_prevents_replaying_cleared_encounters() -> void:
	var director := EncounterDirector.new(ENCOUNTERS)
	director.skip_through(0)
	assert_eq(str(director.try_trigger(9999.0).get("title")), "second")


func test_trigger_x_of_reads_sorted_encounters() -> void:
	var director := EncounterDirector.new(ENCOUNTERS)
	assert_eq(director.trigger_x_of(0), 500.0)
	assert_eq(director.trigger_x_of(1), 2000.0)
