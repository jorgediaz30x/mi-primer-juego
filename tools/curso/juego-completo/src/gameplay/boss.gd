class_name Boss
extends Enemy
## Morvane — the graveyard boss, built like a Cuphead fight: big, telegraphed,
## and changing form between phases.
##
## Lifecycle: INTRO (rises with a title card) -> FIGHT -> dies (level shows KO).
## Forms: "sorcerer" (animations.villain) for phases 1-2, "wraith"
## (animations.wraith) for phase 3; switching plays villain "transform" first.
## Attacks ([BossBrain] pattern names, all telegraphed):
##   "volley"    aimed spread of orbs after a short wind-up
##   "teleport"  smoke out, reappear at another anchor
##   "summon"    asks the level for ceiling spiders
##   "rain"      warning runes, then orbs fall
##   "shockwave" a wave rolls along the floor toward the player: jump it
##   "beam"      a warning line, then a horizontal beam across the arena at a
##               low (jump) or high (stay grounded) height
## Touching him hurts; he cannot be lifted with Aerum or killed by the dash.

## Health changed (for the HUD bar).
signal health_changed(hp: int, max_hp: int)
## The boss wants [param count] extra spiders dropped from the ceiling.
signal summon_requested(count: int)
## A line of boss dialogue/title for the HUD ([param big] = full title card).
signal announced(text: String, big: bool)
## An attack (or the transformation) starts: [param kind] is the pattern name.
signal attacked(kind: String)

var max_hp: int = 90
## World-space x range the boss may occupy (the locked arena view).
var arena_left: float = 0.0
var arena_right: float = 1280.0
var floor_y: float = 620.0
var projectile_parent: Node

## This boss's config section (level "boss").
var _b: GameConfig
var _brain: BossBrain
var _anchor: int = 1
var _hover_base_y: float
var _cast_timer: float = 0.0
var _busy: float = 0.0
var _form: String = "sorcerer"


## Reads tuning from the level's "boss" section. Call after [method Enemy.setup].
func configure(boss: GameConfig) -> void:
	_b = boss
	max_hp = _b.get_int("hp", 90)
	hp = max_hp
	xp_value = _b.get_int("xp", 400)
	points_value = _b.get_int("points", 8000)
	heavy = true
	body_size = _b.get_vec2("size", Vector2(120, 330))
	_brain = BossBrain.new(_b.get_array("phases"))


func _ready() -> void:
	super._ready()
	_attach_form("sorcerer")
	_hover_base_y = floor_y - _b.get_float("hover_height", 10.0)
	global_position = Vector2(_anchor_x(_anchor), _hover_base_y)
	# Intro: rise out of the central tomb while the title card plays.
	_busy = _b.get_float("intro_time", 2.4)
	modulate.a = 0.0
	var art := get_node_or_null(SpriteHook.ART_NODE) as Node2D
	if art:
		art.position.y = body_size.y
		create_tween().tween_property(art, "position:y", 0.0, _busy * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	create_tween().tween_property(self, "modulate:a", 1.0, _busy * 0.4)
	Fx.play(get_parent(), config, "teleport", global_position + Vector2(0, -body_size.y * 0.5), config.get_color("debug.npc"))
	announced.emit.call_deferred("%s\n%s" % [config.get_text("names.boss_title"), config.get_text("names.boss_subtitle")], true)
	health_changed.emit(hp, max_hp)


## Aerum cannot lift the boss.
func can_be_grabbed(_allow_heavy: bool) -> bool:
	return false


## True during the intro and the transformation (hits still land, touching still hurts).
func is_busy() -> bool:
	return _busy > 0.0


## Applies damage and reports the new health.
func hit(damage: int, knock: Vector2, how: String = "bolt") -> void:
	super.hit(damage, Vector2.ZERO, how)
	health_changed.emit(maxi(hp, 0), max_hp)


func _behave(delta: float) -> void:
	global_position.y = _hover_base_y + sin(_anim_time * 2.0) * _b.get_float("hover_bob", 8.0)
	SpriteHook.face(self, signf(target.global_position.x - global_position.x))
	_cast_timer -= delta
	_busy -= delta
	if _cast_timer <= 0.0 and _busy <= 0.0:
		SpriteHook.play(self, "idle")
	if _busy > 0.0:
		return
	var ratio: float = float(hp) / float(max_hp)
	for action in _brain.tick(delta, ratio):
		_perform(action)


func _perform(action: String) -> void:
	var phase: Dictionary = _brain.current()
	attacked.emit(action)
	match action:
		"phase_change":
			_flash = 0.3
			var form: String = str(phase.get("form", _form))
			if form != _form:
				_transform_into(form)
			else:
				_teleport()
		"volley":
			_cast()
			var windup: float = _b.get_float("cast_windup", 0.35)
			_busy = windup
			get_tree().create_timer(windup, false, true).timeout.connect(func() -> void:
				if state == State.ACTIVE:
					_fire_volley(int(phase.get("volley_count", 3)), float(phase.get("orb_speed", 420.0))))
		"teleport":
			_teleport()
		"summon":
			_cast()
			summon_requested.emit(int(phase.get("summon_count", 3)))
		"rain":
			_cast()
			_rain(int(phase.get("rain_count", 5)), float(phase.get("orb_speed", 420.0)))
		"shockwave":
			_cast()
			_shockwave()
		"beam":
			_cast()
			_beam()


# --- Forms -----------------------------------------------------------------

func _attach_form(form: String) -> void:
	var old := get_node_or_null(SpriteHook.ART_NODE)
	if old:
		old.name = "OldArt"
		old.queue_free()
	var who: String = "villain" if form == "sorcerer" else form
	has_art = SpriteHook.attach_character(self, config, who, "idle")
	var art := get_node_or_null(SpriteHook.ART_NODE) as Node2D
	if art:
		art.scale *= _b.get_float("art_scale", 2.0)
	_form = form


func _transform_into(form: String) -> void:
	attacked.emit("transform")
	announced.emit(config.get_text("names.boss_transform"), false)
	var duration: float = _b.get_float("transform_time", 1.6)
	_busy = duration
	if SpriteHook.has_anim(self, "transform"):
		SpriteHook.play(self, "transform")
	Fx.play(get_parent(), config, "teleport", global_position + Vector2(0, -body_size.y * 0.5), config.get_color("debug.npc"))
	get_tree().create_timer(duration, false, true).timeout.connect(func() -> void:
		if state != State.DEAD:
			_attach_form(form)
			Fx.play(get_parent(), config, "explosion", global_position + Vector2(0, -body_size.y * 0.5), config.get_color("debug.npc")))


func _cast() -> void:
	if SpriteHook.has_anim(self, "cast"):
		SpriteHook.play(self, "cast")
		_cast_timer = _b.get_float("cast_anim_time", 0.5)


# --- Attacks -----------------------------------------------------------------

func _fire_volley(count: int, speed: float) -> void:
	var origin := global_position + Vector2(0, -body_size.y * 0.6)
	var aim := (target.global_position + Vector2(0, -50) - origin).normalized()
	var spread: float = deg_to_rad(_b.get_float("volley_spread_degrees", 14.0))
	for i in count:
		var offset: float = (i - (count - 1) * 0.5) * spread
		_spawn_orb(origin, aim.rotated(offset) * speed)


func _rain(count: int, speed: float) -> void:
	var warning_time: float = _b.get_float("rain_warning", 0.7)
	var margin: float = _b.get_float("rain_margin", 80.0)
	for i in count:
		var x: float = lerpf(arena_left + margin, arena_right - margin, (i + 0.5) / count)
		var marker := SpawnWarning.new()
		marker.config = config
		marker.color = config.get_color("debug.warning")
		marker.position = Vector2(x, 60.0)
		projectile_parent.add_child(marker)
		get_tree().create_timer(warning_time + i * 0.08, false, true).timeout.connect(func() -> void:
			if is_instance_valid(marker):
				marker.queue_free()
			if state == State.ACTIVE:
				_spawn_orb(Vector2(x, -30.0), Vector2(0, speed)))


func _shockwave() -> void:
	var wave := BossShockwave.new()
	wave.config = config
	wave.direction = signf(target.global_position.x - global_position.x)
	if wave.direction == 0.0:
		wave.direction = -1.0
	wave.speed = _b.get_float("shockwave_speed", 620.0)
	wave.size = Vector2(_b.get_float("shockwave_width", 90.0), _b.get_float("shockwave_height", 60.0))
	wave.bounds = Vector2(arena_left, arena_right)
	wave.position = Vector2(global_position.x, floor_y)
	projectile_parent.add_child(wave)


func _beam() -> void:
	var heights: Array = _b.get_array("beam_heights")
	var height: float = float(heights[randi() % heights.size()]) if not heights.is_empty() else 40.0
	var beam := BossBeam.new()
	beam.config = config
	beam.span = Vector2(arena_left, arena_right)
	beam.y = floor_y - height
	beam.thickness = _b.get_float("beam_thickness", 90.0)
	beam.warning_time = _b.get_float("beam_warning", 0.9)
	beam.active_time = _b.get_float("beam_time", 0.9)
	beam.target = target as Player
	projectile_parent.add_child(beam)


func _spawn_orb(origin: Vector2, velocity_in: Vector2) -> void:
	var orb := BossOrb.new()
	orb.config = config
	orb.position = origin
	orb.velocity = velocity_in
	orb.radius = _b.get_float("orb_radius", 24.0)
	projectile_parent.add_child(orb)


func _teleport() -> void:
	var anchors: Array = _b.get_array("anchors")
	if anchors.size() < 2:
		return
	Fx.play(get_parent(), config, "teleport", global_position + Vector2(0, -body_size.y * 0.5), config.get_color("debug.npc"))
	var next: int = (_anchor + 1) % anchors.size()
	# Never reappear on top of the player.
	if absf(_anchor_x(next) - target.global_position.x) < body_size.x * 1.5:
		next = (next + 1) % anchors.size()
	_anchor = next
	global_position.x = _anchor_x(_anchor)
	_busy = _b.get_float("teleport_time", 0.5)
	Fx.play(get_parent(), config, "teleport", global_position + Vector2(0, -body_size.y * 0.5), config.get_color("debug.npc"))


func _anchor_x(index: int) -> float:
	var anchors: Array = _b.get_array("anchors")
	var fraction: float = float(anchors[index % anchors.size()]) if not anchors.is_empty() else 0.5
	return lerpf(arena_left, arena_right, fraction)


func _draw_body() -> void:
	DebugBox.draw(self, body_size, tint(config.get_color("debug.npc")))
