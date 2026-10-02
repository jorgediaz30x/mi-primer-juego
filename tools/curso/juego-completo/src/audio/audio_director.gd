class_name AudioDirector
extends Node
## Plays the adaptive music and the sound effects. Paths come from config
## "audio.music.<id>" / "audio.sfx.<id>" (written by tools/audio/generate_audio.py);
## a missing file is simply silent.
##
## Music: two looping players (calm + tension) blended by [MusicMixer] from the
## combat intensity the level reports each frame. A level can also ask for a
## single track (the boss fight).
## SFX: a small pool of players, a minimum interval per sound (ten spiders dying
## in one frame play once) and a little pitch variation so repeats do not tire.
##
## Usage:
##   audio.set_music("forest", "tension")
##   audio.set_target(level.combat_target())   # every frame
##   audio.play("spider_death")
##   audio.apply_settings(settings)            # once at startup, and on Settings.changed
##
## Buses: "Music" and "SFX" are created at runtime (routed to "Master"), so the
## player's master/music/sfx sliders ([Settings]) scale on top of the config's
## own base mix (volumes.music_db / sfx_db / sfx_gain_db) without touching it.

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

var _config: GameConfig
var _mixer: MusicMixer
var _calm: AudioStreamPlayer
var _tension: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _cache: Dictionary = {}
var _last_played: Dictionary = {}
var _target: float = 0.0
var _single_track: bool = false
var _rng := RandomNumberGenerator.new()


## Injects config. Call before adding to the tree.
func setup(config: GameConfig) -> void:
	_config = config


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	_mixer = MusicMixer.new(_config.get_float("audio.intensity.rise", 2.0), _config.get_float("audio.intensity.fall", 0.35))
	_calm = _new_player(MUSIC_BUS)
	_tension = _new_player(MUSIC_BUS)
	for i in _config.get_int("audio.sfx_voices", 12):
		_pool.append(_new_player(SFX_BUS))


func _new_player(bus: String = "Master") -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player


## Creates audio bus [param bus_name] routed to Master if it does not exist
## yet. Idempotent, so it is safe even if an [AudioDirector] were ever rebuilt.
static func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var index := AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")


## Scales the config's base mix by the player's Master/Music/SFX sliders.
## Call once at startup and again whenever [param settings] changes.
func apply_settings(settings: Settings) -> void:
	_set_bus_volume("Master", settings.master_db())
	_set_bus_volume(MUSIC_BUS, settings.music_db())
	_set_bus_volume(SFX_BUS, settings.sfx_db())


static func _set_bus_volume(bus_name: String, db: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index != -1:
		AudioServer.set_bus_volume_db(index, db)


## Starts looping [param calm] and [param tension] (music ids). Same ids keep playing.
## An empty [param tension] plays [param calm] alone at full volume (boss fight).
func set_music(calm: String, tension: String = "") -> void:
	_single_track = tension.is_empty()
	_swap(_calm, calm)
	_swap(_tension, tension)


## Combat intensity the music should move toward (0 calm .. 1 full combat).
func set_target(target: float) -> void:
	_target = target


## Plays sound effect [param id] once (throttled per id).
func play(id: String) -> void:
	var stream := _stream("audio.sfx." + id, false)
	if stream == null:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(id, -99.0)) < _config.get_float("audio.sfx_min_interval", 0.06):
		return
	_last_played[id] = now
	var player := _pool[_next_player]
	_next_player = (_next_player + 1) % _pool.size()
	player.stream = stream
	player.volume_db = _config.get_float("audio.volumes.sfx_db", -4.0) + _config.get_float("audio.sfx_gain_db." + id, 0.0)
	var jitter: float = _config.get_float("audio.pitch_jitter", 0.06)
	player.pitch_scale = 1.0 + _rng.randf_range(-jitter, jitter)
	player.play()


func _process(delta: float) -> void:
	var music_db: float = _config.get_float("audio.volumes.music_db", -8.0)
	if _single_track:
		_calm.volume_db = music_db
		_tension.volume_db = -80.0
		return
	_mixer.update(_target, delta)
	_calm.volume_db = music_db + linear_to_db(maxf(_mixer.calm_gain(), 0.0001))
	_tension.volume_db = music_db + linear_to_db(maxf(_mixer.tension_gain(), 0.0001))


func _swap(player: AudioStreamPlayer, id: String) -> void:
	var stream := _stream("audio.music." + id, true) if not id.is_empty() else null
	if player.stream == stream and (stream == null or player.playing):
		return
	player.stream = stream
	if stream:
		player.play()
	else:
		player.stop()


func _stream(key: String, loop: bool) -> AudioStream:
	if _cache.has(key):
		return _cache[key]
	var path: String = _config.get_text(key)
	var stream: AudioStream = null
	if not path.is_empty() and ResourceLoader.exists(path):
		stream = load(path) as AudioStream
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = loop
	_cache[key] = stream
	return stream
