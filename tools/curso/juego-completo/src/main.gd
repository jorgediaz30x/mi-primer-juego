extends Node2D
## Composition root: builds every dependency once and wires them together.
##
## No autoload singletons — config, progression and save are created here and
## injected, so each piece can be tested on its own.
## Progression is Bloodborne-style: dying costs your position, never what you
## earned. Level, XP and cards persist (and are saved); you respawn at the last
## checkpoint (every cleared zone, and the boss arena door). N starts from zero.
## The game is config "levels" played in order: forest -> cave -> graveyard.

const CONFIG_PATH := "res://assets/data/game_config.json"
## Bump when the meaning of saved data changes.
## v2: three levels (old positions reset). v3: 4-card limit (flags reset so the
## cave's discovery offer shows up once).
const SAVE_VERSION := 3
## Settings (volume, fullscreen) live apart from the run save — see [Settings].
const SETTINGS_PATH := "user://settings.json"

enum RunState { PLAYING, PICKING, DEAD, VICTORY }
## Which full-screen menu is on top, if any. Gates Esc (only pauses from
## NONE+PLAYING) and restart/new-game input (only while NONE).
enum MenuState { NONE, TITLE, PAUSE, OPTIONS, CONTROLS }

var _config: GameConfig
var _deck: UpgradeDeck
var _experience: Experience
var _save: SaveStore
var _settings: Settings
var _settings_store: SaveStore
var _rng := RandomNumberGenerator.new()
var _level: Level
var _hud: Hud
var _level_up: LevelUpScreen
var _crosshair: Crosshair
var _audio: AudioDirector
var _title: TitleScreen
var _pause_menu: PauseMenu
var _options: OptionsScreen
var _controls: ControlsScreen
var _state: RunState = RunState.PLAYING
var _menu: MenuState = MenuState.TITLE
## Which screen (TITLE or PAUSE) Options/Controls should return to when closed.
var _menu_under: MenuState = MenuState.TITLE
## Queued offers: {"heading": String, "featured": Array[String]}.
var _pending_offers: Array[Dictionary] = []
var _best_score: int = 0
var _checkpoint: Dictionary = {}
## Index into config "levels" of the level being played.
var _level_index: int = 0
## Whether a save exists yet — gates "Continuar" on the title screen.
var _has_progress: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputSetup.apply()
	_rng.randomize()
	_config = GameConfig.load_from(CONFIG_PATH)
	DisplayServer.window_set_title(_config.get_text("names.game_title"))
	UiStyle.install_font(_config)

	# QA captures must never read or overwrite the player's real progress.
	var capturing: bool = Array(OS.get_cmdline_user_args()).any(func(arg: Variant) -> bool: return str(arg).begins_with("--capture="))
	_save = SaveStore.new(_config.get_text("progression.qa_save_path", "user://qa_save.json") if capturing else SaveStore.DEFAULT_PATH)
	_settings_store = SaveStore.new(_config.get_text("progression.qa_settings_path", "user://qa_settings.json") if capturing else SETTINGS_PATH)
	_deck = UpgradeDeck.new(_config.get_array("upgrades.pool"), _config.get_int("upgrades.max_owned", 4))
	_experience = Experience.new(
		_config.get_float("progression.xp_base", 60.0),
		_config.get_float("progression.xp_growth", 1.3),
		_config.get_int("progression.max_level", 30))
	_load_progress()
	_experience.leveled_up.connect(_on_leveled_up)
	_deck.changed.connect(_persist)

	_settings = Settings.new(_config)
	_settings.load_state(_settings_store.load_state())
	_settings.changed.connect(_on_settings_changed)

	_hud = Hud.new()
	_hud.setup(_config)
	add_child(_hud)
	_hud.hide()

	_level_up = LevelUpScreen.new()
	_level_up.setup(_config, _deck)
	_level_up.picked.connect(_on_card_picked)
	_level_up.kept.connect(_offer_next)
	_level_up.expired.connect(_on_offer_expired)
	add_child(_level_up)

	_crosshair = Crosshair.new()
	_crosshair.setup(_config)
	add_child(_crosshair)
	_crosshair.set_aiming(false)

	_audio = AudioDirector.new()
	_audio.setup(_config)
	add_child(_audio)
	_audio.apply_settings(_settings)

	_title = TitleScreen.new()
	_title.setup(_config, _has_progress)
	_title.continue_pressed.connect(_start_run)
	_title.new_game_pressed.connect(_new_game)
	_title.options_pressed.connect(_open_options.bind(MenuState.TITLE))
	_title.controls_pressed.connect(_open_controls.bind(MenuState.TITLE))
	_title.quit_pressed.connect(func() -> void: get_tree().quit())
	add_child(_title)

	_pause_menu = PauseMenu.new()
	_pause_menu.setup(_config)
	_pause_menu.resume_pressed.connect(_resume)
	_pause_menu.options_pressed.connect(_open_options.bind(MenuState.PAUSE))
	_pause_menu.controls_pressed.connect(_open_controls.bind(MenuState.PAUSE))
	_pause_menu.title_pressed.connect(_on_pause_to_title)
	add_child(_pause_menu)

	_options = OptionsScreen.new()
	_options.setup(_config)
	_options.master_volume_changed.connect(_settings.set_master_volume)
	_options.music_volume_changed.connect(_settings.set_music_volume)
	_options.sfx_volume_changed.connect(_settings.set_sfx_volume)
	_options.fullscreen_toggled.connect(_settings.set_fullscreen)
	_options.back_pressed.connect(_close_options)
	add_child(_options)

	_controls = ControlsScreen.new()
	_controls.setup(_config)
	_controls.back_pressed.connect(_close_controls)
	add_child(_controls)

	if OS.has_feature("web"):
		_title.interacted.connect(_play_title_music, CONNECT_ONE_SHOT)
	else:
		_play_title_music()

	CaptureTool.maybe_run(self, _level_up)


func _load_progress() -> void:
	var saved := _save.load_state()
	_has_progress = not saved.is_empty()
	_best_score = int(saved.get("best_score", 0))
	var deck_state: Variant = saved.get("deck", {})
	_deck.load_state(deck_state if deck_state is Dictionary else {})
	var xp_state: Variant = saved.get("experience", {})
	_experience.load_state(xp_state if xp_state is Dictionary else {})
	var checkpoint: Variant = saved.get("checkpoint", {})
	_checkpoint = checkpoint if checkpoint is Dictionary else {}
	_level_index = clampi(int(saved.get("level_index", 0)), 0, maxi(0, _config.get_array("levels").size() - 1))
	var version: int = int(saved.get("save_version", 1))
	if version < 2:
		# Positions from an older level layout point outside the new maps:
		# keep cards and XP, restart the journey from the first level.
		_checkpoint = {}
		_level_index = 0
	if version < 3:
		# Cards were already trimmed to the limit by load_state; clear the world
		# flags so discovery offers (e.g. Lumos in the cave) can appear.
		var trimmed := _deck.to_state()
		trimmed["flags"] = []
		_deck.load_state(trimmed)


func _persist() -> void:
	_has_progress = true
	_save.save_state({
		"best_score": _best_score,
		"deck": _deck.to_state(),
		"experience": _experience.to_state(),
		"checkpoint": _checkpoint,
		"level_index": _level_index,
		"save_version": SAVE_VERSION,
	})


## Starts (or restarts) the level at the saved checkpoint — or at the very start.
func _start_run() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	# Guarantees a clean slate regardless of how we got here (the title menu,
	# "R" from QA's CaptureTool, or debug_goto_level) — every overlay hides.
	_menu = MenuState.NONE
	_title.hide()
	_pause_menu.hide()
	_options.hide()
	_controls.hide()
	_hud.show()
	_pending_offers.clear()
	if _level:
		_level.queue_free()
	_level = Level.new()
	_level.process_mode = Node.PROCESS_MODE_PAUSABLE
	var levels: Array = _config.get_array("levels")
	var level_def: Dictionary = levels[_level_index] if _level_index < levels.size() else {}
	_level.setup(_config, _deck, _rng, level_def, _checkpoint)
	_level.player_died.connect(_on_player_died)
	_level.enemy_killed.connect(_on_enemy_killed)
	_level.level_completed.connect(_on_level_completed)
	_level.checkpoint_reached.connect(_on_checkpoint_reached)
	_level.entered_dark.connect(_on_flag_raised.bind("entered_dark"))
	_level.flag_raised.connect(_on_flag_raised)
	_level.sfx.connect(_audio.play)
	_level.music.connect(_audio.set_music)
	add_child(_level)
	move_child(_level, 0)
	_hud.bind_run(_level, _deck, _experience, _best_score)
	_level.player.cast.connect(_crosshair.on_player_cast)
	_crosshair.set_aiming(true)
	_state = RunState.PLAYING


func _process(_delta: float) -> void:
	if _level and is_instance_valid(_level) and _state == RunState.PLAYING:
		_audio.set_target(_level.combat_target())
	else:
		_audio.set_target(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back"):
		_handle_back()
		return
	# Any menu on top (including the card pick) owns input while it is up;
	# restart/new-game must not sneak through underneath it.
	if _menu != MenuState.NONE or _state == RunState.PICKING:
		return
	if event.is_action_pressed("restart"):
		_start_run()
	elif event.is_action_pressed("new_game") and _state in [RunState.DEAD, RunState.VICTORY]:
		_new_game()


## Esc: closes whatever menu is on top, or opens the pause menu during play.
## Never opens over the card pick, the death screen or the victory screen.
func _handle_back() -> void:
	match _menu:
		MenuState.OPTIONS:
			_close_options()
		MenuState.CONTROLS:
			_close_controls()
		MenuState.PAUSE:
			_resume()
		MenuState.TITLE:
			pass
		MenuState.NONE:
			if _state == RunState.PLAYING:
				_open_pause()


func _open_pause() -> void:
	_menu = MenuState.PAUSE
	get_tree().paused = true
	_crosshair.set_aiming(false)
	_pause_menu.open()


func _resume() -> void:
	_menu = MenuState.NONE
	get_tree().paused = false
	_crosshair.set_aiming(true)
	_pause_menu.close()


func _open_options(from: MenuState) -> void:
	_menu_under = from
	if from == MenuState.TITLE:
		_title.hide()
	else:
		_pause_menu.hide()
	_menu = MenuState.OPTIONS
	_options.open(_settings)


func _close_options() -> void:
	_options.close()
	_menu = _menu_under
	if _menu_under == MenuState.TITLE:
		_title.show()
	else:
		_pause_menu.show()


func _open_controls(from: MenuState) -> void:
	_menu_under = from
	if from == MenuState.TITLE:
		_title.hide()
	else:
		_pause_menu.hide()
	_menu = MenuState.CONTROLS
	_controls.open()


func _close_controls() -> void:
	_controls.close()
	_menu = _menu_under
	if _menu_under == MenuState.TITLE:
		_title.show()
	else:
		_pause_menu.show()


## "Volver al inicio": abandons the current level (progress up to the last
## checkpoint is already saved) and shows the title screen again.
func _on_pause_to_title() -> void:
	_pause_menu.close()
	get_tree().paused = false
	Engine.time_scale = 1.0
	if _level and is_instance_valid(_level):
		_level.queue_free()
		_level = null
	_hud.hide()
	_crosshair.set_aiming(false)
	_state = RunState.PLAYING
	_menu = MenuState.TITLE
	_title.refresh(_has_progress)
	_title.show()
	_play_title_music()


func _play_title_music() -> void:
	_audio.set_music(_config.get_text("ui.title.music_id", "boss"))


## Applies [Settings] to the audio buses and the window, and persists them —
## every change from the options screen takes effect immediately.
func _on_settings_changed() -> void:
	_audio.apply_settings(_settings)
	var want_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if _settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want_mode:
		DisplayServer.window_set_mode(want_mode)
	_settings_store.save_state(_settings.to_state())


## QA only (CaptureTool --capture-options): opens Options from the title.
func debug_show_options() -> void:
	_open_options(MenuState.TITLE)


## QA only (CaptureTool --capture-controls): opens Controls from the title.
func debug_show_controls() -> void:
	_open_controls(MenuState.TITLE)


## QA only (CaptureTool --capture-pause): opens the pause menu.
func debug_show_pause() -> void:
	_open_pause()


## Wipes all progress (level, cards, checkpoint) and starts from the beginning.
func _new_game() -> void:
	_deck.load_state({})
	_experience.load_state({})
	_checkpoint = {}
	_level_index = 0
	_persist()
	_start_run()


## QA only (CaptureTool --capture-level): jumps to level [param index] from its start.
func debug_goto_level(index: int) -> void:
	_level_index = clampi(index, 0, _config.get_array("levels").size() - 1)
	_checkpoint = {}
	_start_run()


## QA only (CaptureTool --capture-cards): forces a level-up card offer.
func debug_offer_cards() -> void:
	_on_leveled_up(_experience.level + 1)


func _on_enemy_killed(xp: int, _multiplier: float, _chain: int, _points: int) -> void:
	_experience.add(xp)
	_persist()


func _on_checkpoint_reached(cleared_index: int, x: float) -> void:
	_checkpoint = {"cleared": cleared_index, "x": x}
	_persist()


func _on_leveled_up(new_level: int) -> void:
	_audio.play("level_up")
	_queue_offer(_config.get_text("names.ui_level_up_title") % new_level, [])
	if _level and is_instance_valid(_level):
		Fx.play(_level, _config, "level_up", _level.player.global_position, _config.get_color("ui.accent"))


## First time a world flag is raised (e.g. entering the cave), the cards it
## unlocks are offered right away instead of waiting for a lucky level-up.
func _on_flag_raised(flag: String) -> void:
	if _deck.has_flag(flag):
		return
	_deck.set_flag(flag)
	var unlocked := _deck.cards_unlocked_by(flag)
	if not unlocked.is_empty():
		_queue_offer(_config.get_text("names.ui_discovery_title"), unlocked)


func _queue_offer(heading: String, featured: Array[String]) -> void:
	_pending_offers.append({"heading": heading, "featured": featured})
	if _state == RunState.PLAYING:
		_offer_next()


## Pauses and shows the next queued level-up offer (or resumes when none left).
func _offer_next() -> void:
	while not _pending_offers.is_empty():
		var next: Dictionary = _pending_offers.pop_front()
		var featured: Array[String] = []
		featured.assign(next.get("featured", []))
		var offer := _deck.offer(_rng, _config.get_int("progression.cards_per_offer", 3), featured)
		if offer.is_empty():
			continue
		_state = RunState.PICKING
		get_tree().paused = true
		_crosshair.set_aiming(false)
		_level_up.open(offer, str(next.get("heading", "")))
		return
	_state = RunState.PLAYING
	get_tree().paused = false
	_crosshair.set_aiming(true)


func _on_card_picked(id: String, replaced: String) -> void:
	# A full deck always loses its OLDEST card (the screen already told the player which).
	if replaced.is_empty():
		_deck.take(id)
	else:
		_deck.replace_oldest_with(id)
	_audio.play("card_pick")
	_hud.show_card_taken(id)
	_offer_next()


func _on_offer_expired() -> void:
	_hud.show_announcement(_config.get_text("names.ui_pick_expired"))
	_offer_next()


func _on_player_died() -> void:
	_state = RunState.DEAD
	_record_score()
	_hud.show_death()


func _on_level_completed() -> void:
	_record_score()
	_checkpoint = {}
	var last: bool = _level_index >= _config.get_array("levels").size() - 1
	if not last:
		# Next level, upgrades and XP kept.
		_level_index += 1
		_persist()
		_audio.play("level_complete")
		_hud.show_banner(_config.get_text("names.level_complete"))
		get_tree().create_timer(_config.get_float("progression.level_transition", 2.0)).timeout.connect(_start_run)
		return
	# Beat the final boss: the next attempt starts from level 1, upgrades kept.
	_state = RunState.VICTORY
	_level_index = 0
	_persist()
	_hud.show_victory()


func _record_score() -> void:
	_best_score = maxi(_best_score, _level.score)
	_persist()
