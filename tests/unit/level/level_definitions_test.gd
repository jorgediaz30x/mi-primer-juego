extends "res://tests/test_case.gd"
## Config "levels": forest -> cave -> graveyard, only the last one has a boss.


func _levels() -> Array:
	return GameConfig.load_from("res://assets/data/game_config.json").get_array("levels")


func test_there_are_three_levels_in_order() -> void:
	var ids: Array = _levels().map(func(l: Variant) -> String: return str((l as Dictionary).get("id")))
	assert_eq(ids, ["forest", "cave", "graveyard"])


func test_only_the_last_level_has_a_boss() -> void:
	var levels := _levels()
	for i in levels.size():
		var has_boss: bool = (levels[i] as Dictionary).get("boss") is Dictionary
		assert_eq(has_boss, i == levels.size() - 1, "level %d boss" % i)


func test_every_level_points_at_existing_art_section() -> void:
	var config := GameConfig.load_from("res://assets/data/game_config.json")
	for level: Variant in _levels():
		var art: String = str((level as Dictionary).get("art", ""))
		assert_true(config.get_value("level_art." + art) is Dictionary, "level_art.%s exists" % art)


func test_forest_has_only_spiders() -> void:
	var forest: Dictionary = _levels()[0]
	for encounter: Variant in forest.get("encounters", []):
		for group: Variant in (encounter as Dictionary).get("groups", []):
			assert_eq(str((group as Dictionary).get("type")), "spider")


func test_cave_is_dark_and_raises_card_flags() -> void:
	var cave: Dictionary = _levels()[1]
	assert_true((cave.get("dark_zones", []) as Array).size() > 0, "cave has a dark zone")
	assert_true("entered_dark" in cave.get("flags_on_enter", []), "Lumos cards unlock in the cave")
