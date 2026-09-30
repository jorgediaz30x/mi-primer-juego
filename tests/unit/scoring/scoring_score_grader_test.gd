extends "res://tests/test_case.gd"
## ScoreGrader: thresholds, ordering and edge cases.

const GRADES := [
	{"grade": "C", "min_points": 0},
	{"grade": "S", "min_points": 3000},
	{"grade": "A", "min_points": 2000},
]


func test_points_at_threshold_get_that_grade() -> void:
	assert_eq(ScoreGrader.new(GRADES).grade_for(2000), "A")


func test_points_between_thresholds_get_lower_grade() -> void:
	assert_eq(ScoreGrader.new(GRADES).grade_for(2999), "A")


func test_unsorted_config_still_picks_best_grade() -> void:
	assert_eq(ScoreGrader.new(GRADES).grade_for(99999), "S")


func test_zero_points_get_lowest_grade() -> void:
	assert_eq(ScoreGrader.new(GRADES).grade_for(0), "C")


func test_no_grades_returns_dash() -> void:
	assert_eq(ScoreGrader.new([]).grade_for(500), "-")


func test_config_grades_cover_zero_points() -> void:
	var config := GameConfig.load_from("res://assets/data/game_config.json")
	assert_true(ScoreGrader.new(config.get_array("scoring.grades")).grade_for(0) != "-")
