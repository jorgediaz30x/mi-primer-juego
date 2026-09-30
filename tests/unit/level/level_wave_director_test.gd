extends "res://tests/test_case.gd"
## WaveDirector: event expansion, timing, side alternation and wave progression.

const WAVES := [
	{"title": "one", "groups": [
		{"type": "spider", "mode": "side", "side": "alternate", "count": 3, "interval": 1.0, "delay": 0.0},
		{"type": "werewolf", "mode": "side", "side": "right", "count": 1, "interval": 0.0, "delay": 0.5},
	]},
	{"title": "two", "groups": [
		{"type": "spider", "mode": "ceiling", "count": 2, "interval": 0.5, "delay": 0.0},
	]},
]


func test_start_wave_expands_all_group_events() -> void:
	var director := WaveDirector.new(WAVES)
	director.start_next_wave()
	assert_eq(director.pending_count(), 4)
	assert_eq(director.current_title(), "one")


func test_update_releases_events_in_time_order() -> void:
	var director := WaveDirector.new(WAVES)
	director.start_next_wave()
	var first := director.update(0.0)
	assert_eq(first.size(), 1)
	assert_eq(first[0]["type"], "spider")
	var second := director.update(0.6)
	assert_eq(second.size(), 1)
	assert_eq(second[0]["type"], "werewolf")
	var rest := director.update(5.0)
	assert_eq(rest.size(), 2)
	assert_true(director.all_spawned())


func test_alternate_side_flips_left_right() -> void:
	var director := WaveDirector.new(WAVES)
	director.start_next_wave()
	var events := director.update(10.0)
	var spider_sides: Array = []
	for e in events:
		if e["type"] == "spider":
			spider_sides.append(e["side"])
	assert_eq(spider_sides, ["left", "right", "left"])


func test_wave_progression_ends_after_last_wave() -> void:
	var director := WaveDirector.new(WAVES)
	assert_true(director.has_next_wave())
	director.start_next_wave()
	director.start_next_wave()
	assert_eq(director.current_title(), "two")
	assert_false(director.has_next_wave())
