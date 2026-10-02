extends "res://tests/test_case.gd"
## Settings: defaults from config, clamping, dB conversion, serialization.

const CONFIG_DATA := {
	"settings": {
		"master_volume_default": 0.8,
		"music_volume_default": 0.6,
		"sfx_volume_default": 0.9,
		"fullscreen_default": true,
	}
}


func test_reads_defaults_from_config() -> void:
	var settings := Settings.new(GameConfig.new(CONFIG_DATA))
	assert_near(settings.master_volume, 0.8)
	assert_near(settings.music_volume, 0.6)
	assert_near(settings.sfx_volume, 0.9)
	assert_true(settings.fullscreen)


func test_no_config_falls_back_to_full_volume_and_windowed() -> void:
	var settings := Settings.new()
	assert_near(settings.master_volume, 1.0)
	assert_near(settings.music_volume, 1.0)
	assert_near(settings.sfx_volume, 1.0)
	assert_false(settings.fullscreen)


func test_set_master_volume_clamps_above_one() -> void:
	var settings := Settings.new()
	settings.set_master_volume(1.4)
	assert_near(settings.master_volume, 1.0)


func test_set_sfx_volume_clamps_below_zero() -> void:
	var settings := Settings.new()
	settings.set_sfx_volume(-0.4)
	assert_near(settings.sfx_volume, 0.0)


func test_zero_volume_is_the_db_floor() -> void:
	assert_near(Settings.volume_to_db(0.0), Settings.MIN_DB)


func test_full_volume_is_zero_db() -> void:
	assert_near(Settings.volume_to_db(1.0), 0.0, 0.001)


func test_half_volume_is_about_six_db_down() -> void:
	assert_near(Settings.volume_to_db(0.5), -6.0206, 0.01)


func test_state_round_trips() -> void:
	var settings := Settings.new()
	settings.set_master_volume(0.5)
	settings.set_music_volume(0.25)
	settings.set_sfx_volume(0.75)
	settings.set_fullscreen(true)
	var restored := Settings.new()
	restored.load_state(settings.to_state())
	assert_near(restored.master_volume, 0.5)
	assert_near(restored.music_volume, 0.25)
	assert_near(restored.sfx_volume, 0.75)
	assert_true(restored.fullscreen)


func test_load_state_clamps_invalid_values() -> void:
	var settings := Settings.new()
	settings.load_state({"master_volume": 5.0, "sfx_volume": -1.0})
	assert_near(settings.master_volume, 1.0)
	assert_near(settings.sfx_volume, 0.0)


func test_load_state_keeps_current_value_when_key_missing() -> void:
	var settings := Settings.new()
	settings.set_music_volume(0.42)
	settings.load_state({"master_volume": 0.9})
	assert_near(settings.music_volume, 0.42)
