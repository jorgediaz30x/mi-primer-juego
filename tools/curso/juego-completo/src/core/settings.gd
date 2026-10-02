class_name Settings
extends RefCounted
## Player-tunable audio and display options: master/music/sfx volume (linear
## 0..1) and fullscreen. Pure logic — no filesystem or [AudioServer] access
## here. Persistence reuses [SaveStore] against a separate file
## (user://settings.json, kept apart from the run save); applying the
## volumes to buses and the window mode is [AudioDirector]'s and
## [code]main.gd[/code]'s job.
##
## Usage:
##   var settings := Settings.new(config)
##   settings.set_master_volume(0.8)
##   AudioServer.set_bus_volume_db(idx, settings.master_db())

## Volume at or below this (linear) is treated as silence (avoids -inf dB).
const SILENCE_THRESHOLD := 0.0001
## dB floor for zero volume — audibly silent without being -INF.
const MIN_DB := -80.0

## Emitted after any setter or [method load_state] changes a value.
signal changed

var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0
var fullscreen: bool = false


## Reads defaults from config "settings.*" ([param config] may be null, e.g.
## in tests, to fall back to full volume / windowed).
func _init(config: GameConfig = null) -> void:
	if config == null:
		return
	master_volume = clampf(config.get_float("settings.master_volume_default", 1.0), 0.0, 1.0)
	music_volume = clampf(config.get_float("settings.music_volume_default", 1.0), 0.0, 1.0)
	sfx_volume = clampf(config.get_float("settings.sfx_volume_default", 1.0), 0.0, 1.0)
	fullscreen = bool(config.get_value("settings.fullscreen_default", false))


func set_master_volume(volume: float) -> void:
	master_volume = clampf(volume, 0.0, 1.0)
	changed.emit()


func set_music_volume(volume: float) -> void:
	music_volume = clampf(volume, 0.0, 1.0)
	changed.emit()


func set_sfx_volume(volume: float) -> void:
	sfx_volume = clampf(volume, 0.0, 1.0)
	changed.emit()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	changed.emit()


## Master volume in decibels, for [code]AudioServer.set_bus_volume_db[/code].
func master_db() -> float:
	return Settings.volume_to_db(master_volume)


func music_db() -> float:
	return Settings.volume_to_db(music_volume)


func sfx_db() -> float:
	return Settings.volume_to_db(sfx_volume)


## Converts a linear 0..1 volume to decibels, floored at [const MIN_DB]
## instead of letting a zero volume compute as -INF.
static func volume_to_db(volume: float) -> float:
	if volume <= SILENCE_THRESHOLD:
		return MIN_DB
	return maxf(linear_to_db(volume), MIN_DB)


## Serialisable snapshot (see [SaveStore]).
func to_state() -> Dictionary:
	return {
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"fullscreen": fullscreen,
	}


## Restores a snapshot from [method to_state]. Invalid or missing values fall
## back to the current value (clamped). Emits [signal changed] once.
func load_state(state: Dictionary) -> void:
	master_volume = clampf(float(state.get("master_volume", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(state.get("music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(state.get("sfx_volume", sfx_volume)), 0.0, 1.0)
	fullscreen = bool(state.get("fullscreen", fullscreen))
	changed.emit()
