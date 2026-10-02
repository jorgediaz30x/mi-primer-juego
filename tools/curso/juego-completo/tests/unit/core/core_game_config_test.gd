extends "res://tests/test_case.gd"
## GameConfig: dotted paths, typed getters and colour parsing.

const DATA := {
	"a": {"b": {"c": 5}},
	"hex": "#ff0000",
	"bright": [3, 3, 3],
	"faded": [1, 1, 1, 0.5],
	"vec": [10, 20],
}


func test_dotted_path_reads_nested_value() -> void:
	assert_eq(GameConfig.new(DATA).get_int("a.b.c"), 5)


func test_missing_path_returns_default() -> void:
	assert_eq(GameConfig.new(DATA).get_int("a.x.c", 7), 7)


func test_hex_color_parses() -> void:
	assert_eq(GameConfig.new(DATA).get_color("hex"), Color(1, 0, 0))


func test_array_color_allows_overbright() -> void:
	assert_near(GameConfig.new(DATA).get_color("bright").r, 3.0)


func test_array_color_reads_alpha() -> void:
	assert_near(GameConfig.new(DATA).get_color("faded").a, 0.5)


func test_vec2_parses() -> void:
	assert_eq(GameConfig.new(DATA).get_vec2("vec"), Vector2(10, 20))


func test_merged_overrides_and_merges_nested_dictionaries() -> void:
	var base := {"a": 1, "nested": {"x": 1, "y": 2}}
	var over := {"a": 5, "nested": {"y": 9}}
	var out := GameConfig.merged(base, over)
	assert_eq(out["a"], 5)
	assert_eq(out["nested"], {"x": 1, "y": 9})
	assert_eq(base["nested"]["y"], 2, "inputs untouched")


func test_section_reads_a_sub_dictionary() -> void:
	assert_eq(GameConfig.new(DATA).section("a.b").get_int("c"), 5)

