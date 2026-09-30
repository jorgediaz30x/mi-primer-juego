class_name Level
extends Node2D
## One side-scrolling level (forest, cave or graveyard), built from its entry in
## config "levels" merged over the "level" defaults. The graveyard ends in the
## Morvane fight; the others end when the player reaches the right edge.
##
## Flow: run right -> an encounter triggers at its x -> camera locks, enemies
## pour in from the ceiling, both sides and the ground -> cleared, camera
## unlocks -> ... -> boss arena locks -> Morvane falls -> completed.
## The ground is painted into the level art segments; collision is one flat,
## invisible line at level.floor_y. The level reports outcomes through signals
## and the composition root ([code]main.gd[/code]) decides what they mean.

## Player was caught (emitted after the death slow-mo).
signal player_died
## An enemy died. [param xp] and [param points] already include the combo multiplier.
signal enemy_killed(xp: int, multiplier: float, chain: int, points: int)
## An encounter began (index is 0-based).
signal wave_started(index: int, total: int, title: String)
## The boss appeared.
signal boss_started(boss_name: String, max_hp: int)
## Boss health changed.
signal boss_health_changed(hp: int, max_hp: int)
## Boss defeated and the closing line played.
signal level_completed
## A line to flash on screen.
signal announce(text: String)
## A checkpoint was reached: respawn at [param x] with encounters up to
## [param cleared_index] already done.
signal checkpoint_reached(cleared_index: int, x: float)
## The player stepped into a dark zone for the first time this run.
signal entered_dark
## A world flag the upgrade deck cares about (level "flags_on_enter").
signal flag_raised(flag: String)
## A big centred title (boss title card, KO) or a line ([param big] false).
signal banner(text: String, big: bool)
## A sound effect should play (id of config "audio.sfx").
signal sfx(id: String)
## The music should change: calm + tension track ids ("" tension = single track).
signal music(calm: String, tension: String)

enum Phase { RUN, ENCOUNTER, BOSS, OUTRO, DONE, DEAD }

var player: Player
var phase: Phase = Phase.RUN
## Points scored this run.
var score: int = 0
## Total level width in world pixels.
var length: float = 0.0

var _config: GameConfig
## This level's definition (config "level" defaults + its "levels" entry).
var _lv: GameConfig
## This level's art (config "level_art" shared keys + level_art.<art>).
var _art: GameConfig
var _skills: UpgradeDeck
var _rng: RandomNumberGenerator
var _director: EncounterDirector
var _combo: ComboCounter
var _enemies: Node2D
var _projectiles: Node2D
var _fx: Node2D
var _camera: Camera2D
var _cam_x: float = 0.0
var _locked: bool = false
var _lock_walls: Array[CollisionShape2D] = []
var _shake: float = 0.0
var _timer: float = 0.0
var _pending_spawns: int = 0
var _boss: Boss
var _far: Texture2D
var _segments: Array[Texture2D] = []
var _seam_cover: Texture2D
var _view: Vector2
var _floor: float = 620.0
var _segment_widths: Array[float] = []
## Per-segment vertical shift so every segment's painted floor lands on the collision line.
var _segment_offsets: Array[float] = []
var _darkness: CanvasModulate
var _start: Dictionary = {}
var _was_in_dark: bool = false
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect
var _lightning_timer: float = 0.0
## QA only (CaptureTool --capture-boss-ratio): boss spawns with this hp ratio (0..1).
var debug_boss_hp_ratio: float = -1.0


## Injects dependencies. Call before adding to the tree.
## [param level_def] is an entry of config "levels"; [param checkpoint]
## ({"x", "cleared"}) respawns there with those encounters done.
func setup(cfg: GameConfig, skills: UpgradeDeck, rng: RandomNumberGenerator, level_def: Dictionary, checkpoint: Dictionary = {}) -> void:
	_config = cfg
	var defaults: Variant = cfg.get_value("level", {})
	_lv = GameConfig.new(GameConfig.merged(defaults if defaults is Dictionary else {}, level_def))
	var shared: Variant = cfg.get_value("level_art", {})
	var own: Variant = cfg.get_value("level_art." + str(level_def.get("art", "")), {})
	_art = GameConfig.new(GameConfig.merged(shared if shared is Dictionary else {}, own if own is Dictionary else {}))
	_skills = skills
	_rng = rng
	_start = checkpoint


## The running combo, read by the HUD.
func get_combo() -> ComboCounter:
	return _combo


func _ready() -> void:
	_view = _lv.get_vec2("view_size", Vector2(1280, 720))
	_load_art()
	_resolve_floor()
	_build_collision()
	_build_glow_lights()
	_enemies = _make_layer("Enemies")
	_projectiles = _make_layer("Projectiles")
	_fx = _make_layer("Fx")

	_camera = Camera2D.new()
	add_child(_camera)
	_camera.make_current()

	_build_lightning()

	# Darkness only tints this canvas layer: the HUD (its own CanvasLayer) stays readable.
	_darkness = CanvasModulate.new()
	_darkness.color = Color.WHITE * _lv.get_float("darkness.outside", 1.0)
	add_child(_darkness)

	player = Player.new()
	player.setup(_config, _skills, _projectiles)
	player.position = Vector2(_config.get_float("player.spawn_x", 200.0), _floor_y())
	player.died.connect(_on_player_died)
	player.cast.connect(_on_player_cast)
	player.hurt.connect(_on_player_hurt)
	player.cast.connect(_on_cast_sound)
	add_child(player)

	_director = EncounterDirector.new(_lv.get_array("encounters"))
	_combo = ComboCounter.new(
		_config.get_float("combo.window", 1.6),
		_config.get_float("combo.step_per_kill", 0.25),
		_config.get_float("combo.max_multiplier", 3.0))
	music.emit.call_deferred(_lv.get_text("music.calm"), _lv.get_text("music.tension"))
	for flag: Variant in _lv.get_array("flags_on_enter"):
		flag_raised.emit.call_deferred(str(flag))
	if _start.is_empty():
		_update_camera(1.0)
		announce.emit.call_deferred(_lv.get_text("intro"))
	else:
		_director.skip_through(int(_start.get("cleared", -1)))
		debug_teleport(float(_start.get("x", 200.0)))
		announce.emit.call_deferred(_config.get_text("names.checkpoint_respawn"))


## Draws the foreground tree over every join between two level segments.
## GPT Image segments never line up perfectly; a trunk hides the seam.
func _draw_seam_covers(scale: float, view_rect: Rect2) -> void:
	if _seam_cover == null or _segments.size() < 2:
		return
	var size: Vector2 = _seam_cover.get_size() * scale
	var sink: float = _art.get_float("seam_cover_sink", 24.0)
	var seam_x: float = 0.0
	for i in _segments.size() - 1:
		seam_x += _segment_widths[i]
		var rect := Rect2(Vector2(seam_x - size.x * 0.5, _floor_y() + sink - size.y), size)
		if rect.end.x > view_rect.position.x and rect.position.x < view_rect.end.x:
			draw_texture_rect(_seam_cover, rect, false)


## A real light on every bright spot the art pipeline found in the segments
## (level_art.<art>.glow_points: [x, y, r, g, b] in art pixels), so a cave is lit
## by its own crystals instead of looking like a dimmed picture.
func _build_glow_lights() -> void:
	var points_per_segment: Array = _art.get_array("glow_points")
	if points_per_segment.is_empty():
		return
	var scale: float = _config.get_float("render.pixel_scale", 3.0)
	var texture := Fx.radial_light_texture(Player.LIGHT_TEXTURE_SIZE)
	var radius: float = _art.get_float("glow_light.radius", 150.0)
	var energy: float = _art.get_float("glow_light.energy", 0.9)
	var seg_x: float = 0.0
	for i in _segments.size():
		var points: Variant = points_per_segment[i] if i < points_per_segment.size() else null
		var texture_height: float = _segments[i].get_height() if _segments[i] else _art.get_float("segment_height_px", 240.0)
		if points is Array:
			for p: Variant in points:
				var a: Array = p
				var light := PointLight2D.new()
				light.texture = texture
				light.texture_scale = radius / (Player.LIGHT_TEXTURE_SIZE * 0.5)
				light.energy = energy
				light.color = Color8(int(a[2]), int(a[3]), int(a[4]))
				light.position = Vector2(seg_x + float(a[0]) * scale, _view.y - (texture_height - float(a[1])) * scale + _segment_offset(i))
				add_child(light)
		seg_x += _segment_widths[i]


func _segment_offset(i: int) -> float:
	return _segment_offsets[i] if i < _segment_offsets.size() else 0.0


## QA only: marks every encounter as done so the boss can be reached directly.
func debug_skip_encounters() -> void:
	while _director.next_trigger_x() != INF:
		_director.try_trigger(INF)
		_director.finish()
	phase = Phase.RUN


## QA only (CaptureTool --capture-x): puts the player on the floor at [param x]
## and snaps the camera there, as if they had walked.
func debug_teleport(x: float) -> void:
	player.global_position = Vector2(x, _floor_y())
	player.velocity = Vector2.ZERO
	var lead: float = _lv.get_float("camera.lead", 160.0)
	_cam_x = clampf(x - _view.x * 0.5 + lead, 0.0, maxf(0.0, length - _view.x))
	_update_camera(0.0)


func _make_layer(layer_name: String) -> Node2D:
	var node := Node2D.new()
	node.name = layer_name
	add_child(node)
	return node


# --- Frame loop -----------------------------------------------------------

func _process(delta: float) -> void:
	_shake = maxf(0.0, _shake - _config.get_float("feel.shake_decay", 55.0) * delta)
	_camera.offset = Vector2(_rng.randf_range(-_shake, _shake), _rng.randf_range(-_shake, _shake))
	queue_redraw()


func _physics_process(delta: float) -> void:
	_combo.tick(delta)
	_update_camera(delta)
	_update_darkness(delta)
	_update_lightning(delta)
	match phase:
		Phase.RUN:
			_check_triggers()
		Phase.ENCOUNTER:
			for event: Dictionary in _director.update(delta):
				_spawn_with_warning(event)
			if _director.all_spawned() and _pending_spawns == 0 and _alive_enemies() == 0:
				_director.finish()
				_set_lock(false)
				phase = Phase.RUN
				announce.emit(_config.get_text("names.checkpoint_saved"))
				sfx.emit("checkpoint")
				checkpoint_reached.emit(_director.index, _director.trigger_x_of(_director.index))
		Phase.OUTRO:
			_timer -= delta
			if _timer <= 0.0:
				phase = Phase.DONE
				level_completed.emit()


func _check_triggers() -> void:
	var encounter := _director.try_trigger(player.global_position.x)
	if not encounter.is_empty():
		phase = Phase.ENCOUNTER
		_set_lock(_director.current_locks_camera())
		wave_started.emit(_director.index, _director.count(), _director.current_title())
		return
	if has_boss():
		var arena_x: float = _boss_arena_x()
		if player.global_position.x >= arena_x + _lv.get_float("boss.trigger_offset", 200.0):
			_start_boss(arena_x)
	elif player.global_position.x >= length - _lv.get_float("exit_margin", 120.0):
		# Levels without a boss end at their right edge.
		phase = Phase.OUTRO
		_timer = _lv.get_float("outro_time", 1.2)
		announce.emit(_lv.get_text("outro"))


## This level's title (HUD).
func title() -> String:
	return _lv.get_text("title")


## Occasional full-screen white flashes (levels with boss.lightning_interval).
func _build_lightning() -> void:
	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = 4
	add_child(_flash_layer)
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_layer.add_child(_flash_rect)
	_lightning_timer = _next_lightning()


func _next_lightning() -> float:
	var range: Vector2 = _lv.get_vec2("boss.lightning_interval", Vector2.ZERO)
	return _rng.randf_range(range.x, range.y) if range.y > 0.0 else INF


func _update_lightning(delta: float) -> void:
	_lightning_timer -= delta
	if _lightning_timer > 0.0:
		return
	_lightning_timer = _next_lightning()
	_flash_rect.color.a = 0.75
	create_tween().tween_property(_flash_rect, "color:a", 0.0, _lv.get_float("boss.lightning_flash", 0.18))


## Whether this level ends in a boss fight.
func has_boss() -> bool:
	return _lv.get_value("boss") is Dictionary


# --- Camera ---------------------------------------------------------------

func _update_camera(delta: float) -> void:
	if not _locked:
		var lead: float = _lv.get_float("camera.lead", 160.0)
		var target: float = player.global_position.x - _view.x * 0.5 + lead
		target = clampf(target, 0.0, maxf(0.0, length - _view.x))
		var smoothing: float = _lv.get_float("camera.smoothing", 6.0)
		_cam_x = lerpf(_cam_x, target, clampf(smoothing * delta, 0.0, 1.0))
	_camera.position = Vector2(_cam_x + _view.x * 0.5, _view.y * 0.5)


## Locks the camera on the current view (or at [param at_x]) and raises walls at its edges.
func _set_lock(on: bool, at_x: float = -1.0) -> void:
	_locked = on
	if on and at_x >= 0.0:
		_cam_x = clampf(at_x, 0.0, maxf(0.0, length - _view.x))
	var edges: Array[float] = [_cam_x, _cam_x + _view.x]
	for i in _lock_walls.size():
		var wall := _lock_walls[i]
		(wall.get_parent() as Node2D).position.x = edges[i] + (-20.0 if i == 0 else 20.0)
		wall.set_deferred("disabled", not on)


func _view_left() -> float:
	return _cam_x


func _view_right() -> float:
	return _cam_x + _view.x


# --- Spawning -------------------------------------------------------------

func _alive_enemies() -> int:
	var alive: int = 0
	for child: Node in _enemies.get_children():
		if child is Enemy and (child as Enemy).state != Enemy.State.DEAD and not child.is_queued_for_deletion():
			alive += 1
	return alive


func _spawn_with_warning(event: Dictionary) -> void:
	var mode: String = str(event["mode"])
	var at: Vector2 = _spawn_position(mode, str(event["side"]))
	_pending_spawns += 1
	sfx.emit("warning")
	var marker := SpawnWarning.new()
	marker.config = _config
	marker.color = _config.get_color("debug.warning")
	marker.position = Vector2(at.x, clampf(at.y, 60.0, _floor_y() - 40.0))
	_fx.add_child(marker)
	var wait: float = _config.get_float("feel.spawn_warning_time", 0.5)
	get_tree().create_timer(wait, false, true).timeout.connect(func() -> void:
		marker.queue_free()
		_pending_spawns -= 1
		if phase == Phase.ENCOUNTER or phase == Phase.BOSS:
			_spawn(str(event["type"]), mode, at))


func _spawn_position(mode: String, side: String) -> Vector2:
	var margin: float = _lv.get_float("spawn_margin", 60.0)
	var left: float = _view_left() + margin
	var right: float = _view_right() - margin
	match mode:
		"ceiling":
			return Vector2(_rng.randf_range(left + 60.0, right - 60.0), -30.0)
		"burrow":
			var min_distance: float = _lv.get_float("burrow_min_distance", 250.0)
			var x: float = player.global_position.x
			for attempt in 8:
				x = _rng.randf_range(left, right)
				if absf(x - player.global_position.x) >= min_distance:
					break
			return Vector2(x, _floor_y() + 40.0)
		_:
			var resolved: String = side
			if side not in ["left", "right"]:
				resolved = "left" if _rng.randf() < 0.5 else "right"
			return Vector2(left if resolved == "left" else right, _floor_y() - 4.0)


func _spawn(type: String, mode: String, at: Vector2) -> void:
	var enemy: Enemy
	if type == "werewolf":
		var wolf := Werewolf.new()
		wolf.setup(_config, player)
		wolf.configure()
		enemy = wolf
	else:
		var spider := Spider.new()
		spider.setup(_config, player)
		spider.configure(mode, _rng)
		enemy = spider
	enemy.position = at
	sfx.emit("spider_spawn" if enemy is Spider else "wolf_roar")
	enemy.damaged.connect(_on_enemy_damaged)
	if enemy is Werewolf:
		(enemy as Werewolf).telegraphed.connect(func() -> void: sfx.emit("wolf_roar"))
	enemy.killed.connect(_on_enemy_killed)
	enemy.exploded.connect(_on_exploded)
	_enemies.add_child(enemy)


# --- Boss -----------------------------------------------------------------

func _boss_arena_x() -> float:
	# The arena is the last screen of the level.
	return maxf(0.0, length - _view.x)


func _start_boss(arena_x: float) -> void:
	phase = Phase.BOSS
	checkpoint_reached.emit(_director.count() - 1, arena_x + _lv.get_float("boss.checkpoint_offset", 60.0))
	_set_lock(true, arena_x)
	_boss = Boss.new()
	_boss.setup(_config, player)
	_boss.configure(_lv.section("boss"))
	_boss.arena_left = _view_left()
	_boss.arena_right = _view_right()
	_boss.floor_y = _floor_y()
	_boss.projectile_parent = _projectiles
	_boss.killed.connect(_on_boss_killed)
	_boss.health_changed.connect(func(hp: int, max_hp: int) -> void: boss_health_changed.emit(hp, max_hp))
	_boss.summon_requested.connect(_on_boss_summon)
	_boss.announced.connect(func(text: String, big: bool) -> void: banner.emit(text, big))
	_boss.attacked.connect(_on_boss_attack)
	_boss.damaged.connect(_on_enemy_damaged)
	sfx.emit("boss_intro")
	music.emit(_lv.get_text("boss.music", "boss"), "")
	_enemies.add_child(_boss)
	_shake = _config.get_float("feel.shake_explosion", 16.0)
	boss_started.emit(_config.get_text("names.villain"), _boss.max_hp)
	if debug_boss_hp_ratio >= 0.0:
		_boss.hp = maxi(1, roundi(_boss.max_hp * debug_boss_hp_ratio))
		_boss.health_changed.emit(_boss.hp, _boss.max_hp)


func _on_boss_summon(count: int) -> void:
	for i in count:
		_spawn_with_warning({"type": "spider", "mode": "ceiling", "side": "random"})


func _on_boss_killed(enemy: Enemy, how: String) -> void:
	_on_enemy_killed(enemy, how)
	music.emit("", "")
	for child: Node in _enemies.get_children():
		if child is Enemy and child != enemy:
			(child as Enemy).die("explosion")
	for child: Node in _projectiles.get_children():
		if child is BossOrb:
			child.queue_free()
	Fx.play(_fx, _config, "explosion", enemy.global_position + Vector2(0, -enemy.body_size.y * 0.5), _config.get_color("debug.held"))
	_shake = _config.get_float("feel.shake_death", 22.0)
	phase = Phase.OUTRO
	_timer = _lv.get_float("villain_duration", 3.5)
	banner.emit(_config.get_text("names.boss_knockout"), true)


# --- Feel & outcomes ------------------------------------------------------

## Combat intensity for the adaptive music: nearest enemy + whether a fight is on.
func combat_target() -> float:
	var nearest: float = -1.0
	for child: Node in _enemies.get_children():
		var enemy := child as Enemy
		if enemy and enemy.state != Enemy.State.DEAD:
			var d: float = enemy.global_position.distance_to(player.global_position)
			if nearest < 0.0 or d < nearest:
				nearest = d
	var fighting: bool = phase == Phase.ENCOUNTER or phase == Phase.BOSS
	return MusicMixer.target_for(nearest, _config.get_float("audio.intensity.danger_range", 650.0),
		fighting, _config.get_float("audio.intensity.fight_floor", 0.55))


func _on_cast_sound(kind: String) -> void:
	var ids := {"bolt": "bolt_cast", "nova": "nova", "lumos": "lumos", "dash": "dash", "grab": "levitate", "throw": "throw"}
	if ids.has(kind):
		sfx.emit(str(ids[kind]))


func _on_enemy_damaged(enemy: Enemy, how: String) -> void:
	if enemy is Boss:
		sfx.emit("boss_hurt")
	elif enemy is Werewolf:
		sfx.emit("wolf_hurt")
	if how == "bolt":
		sfx.emit("bolt_hit")


func _on_boss_attack(kind: String) -> void:
	var ids := {"volley": "boss_orb", "teleport": "boss_teleport", "summon": "boss_cast", "rain": "boss_cast",
		"shockwave": "boss_shockwave", "beam": "boss_beam", "transform": "boss_transform"}
	if ids.has(kind):
		sfx.emit(str(ids[kind]))


func _on_enemy_killed(enemy: Enemy, _how: String) -> void:
	if enemy is Boss:
		sfx.emit("boss_death")
	elif enemy is Werewolf:
		sfx.emit("wolf_death")
	else:
		sfx.emit("spider_death")
	var multiplier: float = _combo.register_kill()
	var gained: int = roundi(enemy.xp_value * multiplier)
	var points: int = roundi(enemy.points_value * multiplier)
	score += points
	if not enemy is Boss:
		var color := _config.get_color("debug.enemy_heavy" if enemy is Werewolf else "debug.enemy")
		Fx.play(_fx, _config, "death_puff", enemy.global_position + Vector2(0, -enemy.body_size.y * 0.5), color)
	_shake = maxf(_shake, _config.get_float("feel.shake_kill", 7.0))
	_hitstop(_config.get_float("feel.hitstop_kill", 0.035))
	enemy_killed.emit(gained, multiplier, _combo.count, points)


func _on_exploded(at: Vector2, radius: float) -> void:
	sfx.emit("explosion")
	Fx.play(_fx, _config, "explosion", at, _config.get_color("debug.held"))
	_shake = _config.get_float("feel.shake_explosion", 16.0)
	for child: Node in _enemies.get_children():
		var enemy := child as Enemy
		if enemy and enemy.is_dangerous() and enemy.global_position.distance_to(at) <= radius:
			var damage: int = _config.get_int("spells.levitate.explosion_boss_damage", 3) if enemy is Boss else 99
			enemy.hit(damage, (enemy.global_position - at).normalized() * 400.0, "explosion")


## Fades the world toward level_art.darkness.inside while the player is in a
## dark zone (level.dark_zones = [[x0, x1], ...]); Lumos is the way to see.
func _update_darkness(delta: float) -> void:
	var inside: bool = false
	for zone: Variant in _lv.get_array("dark_zones"):
		var z: Array = zone
		if player.global_position.x >= float(z[0]) and player.global_position.x <= float(z[1]):
			inside = true
			break
	player.lumos_allowed = inside
	if inside and not _was_in_dark:
		announce.emit(_config.get_text("names.dark_hint"))
		entered_dark.emit()
	_was_in_dark = inside
	var level: float = _lv.get_float("darkness.inside" if inside else "darkness.outside", 1.0)
	var target := Color(level, level, level * 1.1, 1.0)
	var fade: float = _lv.get_float("darkness.fade", 2.0)
	_darkness.color = _darkness.color.lerp(target, clampf(fade * delta, 0.0, 1.0))


func _on_player_hurt() -> void:
	sfx.emit("player_hurt")
	_shake = _config.get_float("feel.shake_explosion", 16.0)
	_hitstop(_config.get_float("feel.hitstop_kill", 0.035) * 2.0)


func _on_player_cast(kind: String) -> void:
	match kind:
		"throw":
			_shake = maxf(_shake, 4.0)
		"bolt":
			_shake = maxf(_shake, _config.get_float("feel.shake_shot", 2.0))


func _on_player_died() -> void:
	if phase == Phase.DEAD:
		return
	phase = Phase.DEAD
	sfx.emit("player_death")
	Fx.play(_fx, _config, "death_puff", player.global_position + Vector2(0, -60), _config.get_color("debug.player"))
	_shake = _config.get_float("feel.shake_death", 22.0)
	Engine.time_scale = _config.get_float("feel.death_slowmo_scale", 0.3)
	get_tree().create_timer(_config.get_float("feel.death_screen_delay", 0.55), true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = 1.0
		_enemies.process_mode = Node.PROCESS_MODE_DISABLED
		_projectiles.process_mode = Node.PROCESS_MODE_DISABLED
		player_died.emit())


func _hitstop(duration: float) -> void:
	if phase == Phase.DEAD:
		return
	Engine.time_scale = _config.get_float("feel.hitstop_scale", 0.05)
	get_tree().create_timer(duration, true, false, true).timeout.connect(func() -> void:
		if phase != Phase.DEAD:
			Engine.time_scale = 1.0)


# --- World ----------------------------------------------------------------

func _floor_y() -> float:
	return _floor


## Collision floor: where the art pipeline found the painted ground (median of
## level_art.floor_rows across segments), else the level.floor_y fallback.
func _resolve_floor() -> void:
	_floor = _lv.get_float("floor_y", 620.0)
	var rows: Array = _art.get_array("floor_rows").filter(func(r: Variant) -> bool: return r != null)
	if rows.is_empty() or _segments.is_empty():
		return
	rows.sort()
	var row: float = float(rows[rows.size() / 2])
	# Segments whose ground was painted a few rows higher or lower are shifted to
	# the shared floor: no steps at the joins.
	var all_rows: Array = _art.get_array("floor_rows")
	var shift_scale: float = _config.get_float("render.pixel_scale", 3.0)
	_segment_offsets.clear()
	for i in _segments.size():
		var own: Variant = all_rows[i] if i < all_rows.size() else null
		_segment_offsets.append((row - float(own)) * shift_scale if own != null else 0.0)
	var scale: float = _config.get_float("render.pixel_scale", 3.0)
	var art_height: float = _art.get_float("segment_height_px", 240.0)
	for texture in _segments:
		if texture:
			art_height = texture.get_height()
			break
	_floor = _view.y - (art_height - row) * scale + _lv.get_float("floor_art_offset", 0.0)


func _load_art() -> void:
	_far = SpriteHook.load_texture(_art.get_text("far"))
	_seam_cover = SpriteHook.load_texture(_art.get_text("seam_cover"))
	var scale: float = _config.get_float("render.pixel_scale", 3.0)
	length = 0.0
	var fallback_width: float = _art.get_float("segment_width_px", 720.0) * scale
	for path: Variant in _art.get_array("segments"):
		var texture: Texture2D = SpriteHook.load_texture(str(path)) if path != null else null
		_segments.append(texture)
		var width: float = texture.get_width() * scale if texture else fallback_width
		_segment_widths.append(width)
		length += width
	if length <= 0.0:
		length = _lv.get_float("fallback_length", 8640.0)


func _build_collision() -> void:
	_add_static(Rect2(-200.0, _floor_y(), length + 400.0, 400.0))
	_add_static(Rect2(-80.0, -400.0, 80.0, 1600.0))
	_add_static(Rect2(length, -400.0, 80.0, 1600.0))
	for i in 2:
		_lock_walls.append(_add_static(Rect2(-20.0, -400.0, 40.0, 1600.0), true))


func _add_static(rect: Rect2, disabled: bool = false) -> CollisionShape2D:
	var body := StaticBody2D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = rect.get_center()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.disabled = disabled
	body.add_child(shape)
	add_child(body)
	return shape


func _draw() -> void:
	var scale: float = _config.get_float("render.pixel_scale", 3.0)
	var view_rect := Rect2(_view_left() - 40.0, 0.0, _view.x + 80.0, _view.y)
	draw_rect(view_rect, _art.get_color("sky_color", Color(0.03, 0.04, 0.08)))
	if _far:
		# Parallax: the far layer scrolls at a fraction of the camera speed.
		var parallax: float = _art.get_float("far_parallax", 0.2)
		var size: Vector2 = _far.get_size() * scale
		var start: float = _cam_x * (1.0 - parallax)
		var tile: int = int(floorf((_view_left() - start) / size.x))
		var x: float = start + tile * size.x
		while x < _view_right() + 40.0:
			# Every other copy is mirrored, so neighbouring edges always match:
			# the far art is not seamless, a mirrored repeat is.
			var top: float = _view.y - size.y
			if tile % 2 != 0:
				# A negative-size rect draws nothing; mirror with a transform instead.
				draw_set_transform(Vector2(x + size.x, top), 0.0, Vector2(-1.0, 1.0))
				draw_texture_rect(_far, Rect2(Vector2.ZERO, size), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				draw_texture_rect(_far, Rect2(Vector2(x, top), size), false)
			x += size.x
			tile += 1
	var seg_x: float = 0.0
	for i in _segments.size():
		var texture := _segments[i]
		var width: float = _segment_widths[i]
		if texture and seg_x + width > view_rect.position.x and seg_x < view_rect.end.x:
			var size: Vector2 = texture.get_size() * scale
			draw_texture_rect(texture, Rect2(Vector2(seg_x, _view.y - size.y + _segment_offset(i)), size), false)
		elif texture == null and seg_x + width > view_rect.position.x and seg_x < view_rect.end.x:
			draw_rect(Rect2(seg_x, _floor_y(), width, _view.y - _floor_y()), _config.get_color("debug.world"))
		seg_x += width
	_draw_seam_covers(scale, view_rect)
	if _segments.is_empty():
		draw_rect(Rect2(view_rect.position.x, _floor_y(), view_rect.size.x, _view.y - _floor_y()), _config.get_color("debug.world"))
