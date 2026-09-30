extends "res://tests/test_case.gd"
## MusicMixer: intensity easing, equal-power gains, target from proximity.


func test_at_rest_only_calm_plays() -> void:
	var mixer := MusicMixer.new()
	assert_near(mixer.calm_gain(), 1.0)
	assert_near(mixer.tension_gain(), 0.0)


func test_gains_keep_equal_power_through_the_crossfade() -> void:
	var mixer := MusicMixer.new()
	for step in 11:
		mixer.intensity = step / 10.0
		var power: float = mixer.calm_gain() ** 2 + mixer.tension_gain() ** 2
		assert_near(power, 1.0, 0.0001, "intensity %.1f" % mixer.intensity)


func test_intensity_rises_fast_and_falls_slow() -> void:
	var mixer := MusicMixer.new(2.0, 0.5)
	mixer.update(1.0, 0.25)
	assert_near(mixer.intensity, 0.5)
	mixer.update(0.0, 0.5)
	assert_near(mixer.intensity, 0.25)


func test_target_grows_as_enemy_gets_closer() -> void:
	assert_near(MusicMixer.target_for(600.0, 600.0, false, 0.5), 0.0)
	assert_near(MusicMixer.target_for(300.0, 600.0, false, 0.5), 0.5)
	assert_near(MusicMixer.target_for(0.0, 600.0, false, 0.5), 1.0)


func test_fight_sets_a_floor_and_no_enemy_is_calm() -> void:
	assert_near(MusicMixer.target_for(-1.0, 600.0, true, 0.55), 0.55)
	assert_near(MusicMixer.target_for(-1.0, 600.0, false, 0.55), 0.0)
