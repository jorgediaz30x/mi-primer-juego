class_name Player
extends CharacterBody2D
## The young wizard: tight platforming, Fulgor (bolt), Aerum (grab & throw),
## Nova (radial burst, unlocked by a card), Lumos (light) and the dash.
##
## Hearts: starts with player.max_hearts (1 = one-hit death); heart cards add
## more. Every number comes from config + [UpgradeDeck] modifiers.

## Emitted once when the last heart is lost.
signal died
## Emitted when a spell is cast ("bolt", "nova", "lumos", "grab", "throw", "dash").
signal cast(kind: String)
## Emitted when hearts change (hit taken or a heart card picked).
signal hearts_changed(current: int, maximum: int)
## Emitted when a hit is taken but the player survives.
signal hurt

const LIGHT_TEXTURE_SIZE := 256

var alive: bool = true
## Lumos only works where it matters (dark zones); the level sets this every frame.
var lumos_allowed: bool = false
## QA only (CaptureTool --capture-god): nothing can hurt the player.
var debug_invulnerable: bool = false
var aim: Vector2 = Vector2.RIGHT

var _config: GameConfig
var _skills: UpgradeDeck
var _projectiles: Node

var _coyote: float = 0.0
var _buffer: float = 0.0
var _air_jumps_left: int = 0
var _dash_time: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_dir: float = 1.0
var _bolt_cooldown: float = 0.0
var _levitate_cooldown: float = 0.0
var _grabbed: Enemy = null
var _grab_time: float = 0.0
var _facing: float = 1.0
var _squash: Vector2 = Vector2.ONE
var _was_on_floor: bool = true
var _hurtbox: Area2D
var _has_art: bool = false
var _cast_anim_time: float = 0.0
var _bolt_cooldown_max: float = 1.0
var _levitate_cooldown_max: float = 1.0
var _dash_cooldown_max: float = 1.0
var _nova_cooldown: float = 0.0
var _nova_cooldown_max: float = 1.0
var _lumos_time: float = 0.0
var _lumos_cooldown: float = 0.0
var _lumos_cooldown_max: float = 1.0
var _light: PointLight2D
var _lumos_orb: Node2D
var _hearts: int = 1
var _max_hearts: int = 1
var _hurt_time: float = 0.0


## Injects config, progression and the node that will own projectiles.
func setup(cfg: GameConfig, skills: UpgradeDeck, projectile_parent: Node) -> void:
	_config = cfg
	_skills = skills
	_projectiles = projectile_parent


func _ready() -> void:
	add_to_group("players")
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD
	var hitbox: Vector2 = _config.get_vec2("player.hitbox", Vector2(26, 44))
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = hitbox
	shape.shape = rect
	shape.position = Vector2(0, -hitbox.y * 0.5)
	add_child(shape)

	var hurt_size: Vector2 = _config.get_vec2("player.hurtbox", Vector2(16, 34))
	_hurtbox = Area2D.new()
	_hurtbox.collision_layer = 0
	_hurtbox.collision_mask = Layers.ENEMY
	var hurt_shape := CollisionShape2D.new()
	var hurt_rect := RectangleShape2D.new()
	hurt_rect.size = hurt_size
	hurt_shape.shape = hurt_rect
	hurt_shape.position = Vector2(0, -hitbox.y * 0.5)
	_hurtbox.add_child(hurt_shape)
	add_child(_hurtbox)
	_has_art = SpriteHook.attach_character(self, _config, "hero", "idle")
	_build_light()
	_max_hearts = _heart_capacity()
	_hearts = _max_hearts
	_skills.changed.connect(_on_upgrades_changed)


## World point spells come out of (the wand hand): aim is measured from here
## and every projectile spawns on the line from here toward the crosshair.
func cast_origin() -> Vector2:
	var height: float = _config.get_vec2("player.hitbox", Vector2(42, 130)).y
	return global_position + Vector2(0, -height * _config.get_float("player.cast_height", 0.55))


## QA only (CaptureTool --capture-lumos): lights Lumos as if F was pressed.
func debug_cast_lumos() -> void:
	_lumos_time = _config.get_float("spells.lumos.duration", 8.0) + _skills.get_modifier("lumos.duration")


## Current hearts.
func hearts() -> int:
	return _hearts


## Maximum hearts right now (base + cards).
func max_hearts() -> int:
	return _max_hearts


## Whether the Nova card has been taken.
func nova_unlocked() -> bool:
	return _skills.get_modifier("nova.unlocked") > 0.0


## Readiness of Nova, 0..1 (0 while locked).
func nova_ready() -> float:
	if not nova_unlocked():
		return 0.0
	return 1.0 - clampf(_nova_cooldown / _nova_cooldown_max, 0.0, 1.0)


## Readiness of Lumos, 0..1 (0 while lit or recharging).
func lumos_ready() -> float:
	if _lumos_time > 0.0:
		return 0.0
	return 1.0 - clampf(_lumos_cooldown / _lumos_cooldown_max, 0.0, 1.0)


## A hit from an enemy or projectile. Costs a heart; the last one kills.
## [param from] is where the hit came from (for knockback).
func take_hit(from: Vector2) -> void:
	if not alive or is_invulnerable():
		return
	_hearts -= 1
	hearts_changed.emit(_hearts, _max_hearts)
	if _hearts <= 0:
		die()
		return
	_hurt_time = _config.get_float("player.hurt_invulnerability", 1.2)
	var away: float = signf(global_position.x - from.x)
	if away == 0.0:
		away = -_facing
	velocity = Vector2(away * _config.get_float("player.hurt_knockback", 520.0), _config.get_float("player.hurt_hop", -380.0))
	hurt.emit()


## Readiness of Fulgor, 0 (just cast) .. 1 (ready). For the HUD.
func bolt_ready() -> float:
	return 1.0 - clampf(_bolt_cooldown / _bolt_cooldown_max, 0.0, 1.0)


## Readiness of Aerum, 0..1. Holding an enemy counts as not ready.
func levitate_ready() -> float:
	if _grabbed != null:
		return 0.0
	return 1.0 - clampf(_levitate_cooldown / _levitate_cooldown_max, 0.0, 1.0)


## Readiness of the dash, 0..1.
func dash_ready() -> float:
	return 1.0 - clampf(_dash_cooldown / _dash_cooldown_max, 0.0, 1.0)


## True while dashing or just after a hit: enemies cannot hurt the player.
func is_invulnerable() -> bool:
	return _dash_time > 0.0 or _hurt_time > 0.0 or debug_invulnerable


## Kills the player (idempotent).
func die() -> void:
	if not alive:
		return
	alive = false
	_release_grab(false)
	died.emit()
	hide()


func _physics_process(delta: float) -> void:
	if not alive:
		return
	aim = AimLine.direction(cast_origin(), get_global_mouse_position(), aim)

	_tick_timers(delta)
	_move(delta)
	_cast_bolt()
	_cast_nova()
	_cast_lumos(delta)
	_cast_levitate(delta)
	_check_hurt()
	_squash = _squash.lerp(Vector2.ONE, 12.0 * delta)
	SpriteHook.face(self, _facing)
	_animate(delta)
	var blinking: bool = _hurt_time > 0.0 and int(_hurt_time * 12.0) % 2 == 0
	var ghost: bool = _dash_time > 0.0 or blinking
	SpriteHook.tint(self, _config.get_color("feel_tints.invulnerable", Color(1, 1, 1, 0.45)) if ghost else Color.WHITE)
	queue_redraw()


func _tick_timers(delta: float) -> void:
	_bolt_cooldown -= delta
	_levitate_cooldown -= delta
	_dash_cooldown -= delta
	_nova_cooldown -= delta
	_lumos_cooldown -= delta
	_hurt_time -= delta
	_buffer -= delta
	if Input.is_action_just_pressed("jump"):
		_buffer = _config.get_float("player.jump_buffer", 0.12)
	if is_on_floor():
		_coyote = _config.get_float("player.coyote_time", 0.1)
		_air_jumps_left = int(_skills.get_modifier("move.air_jumps"))
	else:
		_coyote -= delta


func _move(delta: float) -> void:
	var p := "player."
	var input_x: float = Input.get_axis("move_left", "move_right")
	# Facing follows the aim (mouse) so the wizard always turns toward his target;
	# "move" mode restores facing the walking direction.
	if _config.get_text("player.facing_mode", "aim") == "aim" and absf(aim.x) > 0.05:
		_facing = signf(aim.x)
	elif input_x != 0.0:
		_facing = signf(input_x)

	if Input.is_action_just_pressed("dash") and _dash_cooldown <= 0.0:
		_dash_time = _config.get_float(p + "dash_time", 0.14)
		_dash_cooldown = maxf(0.05, _config.get_float(p + "dash_cooldown", 0.45) + _skills.get_modifier("move.dash_cooldown"))
		_dash_cooldown_max = _dash_cooldown
		_dash_dir = signf(input_x) if input_x != 0.0 else _facing
		_squash = Vector2(1.4, 0.7)
		cast.emit("dash")

	if _dash_time > 0.0:
		_dash_time -= delta
		velocity = Vector2(_dash_dir * _config.get_float(p + "dash_speed", 1100.0), 0.0)
		move_and_slide()
		_dash_strike()
		return

	var target_speed: float = input_x * _config.get_float(p + "run_speed", 430.0) * (1.0 + _skills.get_modifier("move.speed_mult"))
	var rate: float
	if not is_on_floor():
		rate = _config.get_float(p + "air_accel", 2400.0)
	elif input_x != 0.0:
		rate = _config.get_float(p + "ground_accel", 3200.0)
	else:
		rate = _config.get_float(p + "ground_friction", 3800.0)
	velocity.x = move_toward(velocity.x, target_speed, rate * delta)

	var g: float = _config.get_float(p + "gravity", 1900.0) if velocity.y < 0.0 else _config.get_float(p + "fall_gravity", 2800.0)
	velocity.y = minf(velocity.y + g * delta, _config.get_float(p + "max_fall_speed", 1150.0))

	if _buffer > 0.0 and (_coyote > 0.0 or _air_jumps_left > 0):
		if _coyote <= 0.0:
			_air_jumps_left -= 1
		velocity.y = _config.get_float(p + "jump_velocity", -760.0)
		_buffer = 0.0
		_coyote = 0.0
		_squash = Vector2(0.7, 1.35)
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= _config.get_float(p + "jump_cut", 0.45)

	move_and_slide()
	if is_on_floor() and not _was_on_floor:
		_squash = Vector2(1.3, 0.75)
	_was_on_floor = is_on_floor()


func _cast_bolt() -> void:
	if not Input.is_action_pressed("cast_bolt") or _bolt_cooldown > 0.0 or _grabbed != null:
		return
	var p := "spells.bolt."
	_bolt_cooldown = maxf(
		_config.get_float(p + "cooldown", 0.24) + _skills.get_modifier("bolt.cooldown"),
		_config.get_float(p + "min_cooldown", 0.08))
	_bolt_cooldown_max = _bolt_cooldown
	var shots: int = _config.get_int(p + "shots", 1) + int(_skills.get_modifier("bolt.shots"))
	var spread: float = deg_to_rad(_config.get_float(p + "spread_degrees", 9.0))
	# Spawned ON the aim line (origin + aim * offset), so the bolt crosses the
	# crosshair centre. Aiming from one point and spawning from another made
	# every shot fly parallel to the aim, above the target.
	var origin := AimLine.spawn_point(cast_origin(), aim, _config.get_float(p + "muzzle_offset", 34.0))
	Fx.play(_projectiles, _config, "muzzle", origin, _config.get_color("debug.projectile"))
	for i in shots:
		var offset: float = (i - (shots - 1) * 0.5) * spread
		var bolt := Bolt.new()
		bolt.position = origin
		bolt.velocity = aim.rotated(offset) * _config.get_float(p + "speed", 1150.0)
		bolt.damage = _config.get_int(p + "damage", 1) + int(_skills.get_modifier("bolt.damage"))
		bolt.pierce = _config.get_int(p + "pierce", 0) + int(_skills.get_modifier("bolt.pierce"))
		bolt.lifetime = _config.get_float(p + "lifetime", 0.9)
		bolt.radius = _config.get_float(p + "radius", 7.0)
		bolt.knockback = _config.get_float(p + "knockback", 160.0)
		bolt.color = _config.get_color("debug.projectile")
		bolt.config = _config
		_projectiles.add_child(bolt)
	velocity -= aim * 40.0
	_cast_anim_time = _config.get_float("player.cast_anim_time", 0.18)
	cast.emit("bolt")


## Nova: a ring of bolts in every direction (needs the Nova card).
func _cast_nova() -> void:
	if not Input.is_action_just_pressed("cast_nova") or not nova_unlocked() or _nova_cooldown > 0.0:
		return
	var p := "spells.nova."
	_nova_cooldown = _config.get_float(p + "cooldown", 2.5)
	_nova_cooldown_max = _nova_cooldown
	var count: int = _config.get_int(p + "count", 6) + int(_skills.get_modifier("nova.count"))
	var origin := cast_origin()
	Fx.play(_projectiles, _config, "explosion", origin, _config.get_color("debug.projectile"))
	for i in count:
		var bolt := Bolt.new()
		bolt.position = origin
		bolt.velocity = Vector2.RIGHT.rotated(TAU * i / count) * _config.get_float(p + "speed", 1100.0)
		bolt.damage = _config.get_int(p + "damage", 1) + int(_skills.get_modifier("bolt.damage"))
		bolt.pierce = int(_skills.get_modifier("bolt.pierce"))
		bolt.lifetime = _config.get_float(p + "lifetime", 0.7)
		bolt.radius = _config.get_float("spells.bolt.radius", 14.0)
		bolt.knockback = _config.get_float("spells.bolt.knockback", 260.0)
		bolt.color = _config.get_color("debug.projectile")
		bolt.config = _config
		_projectiles.add_child(bolt)
	_cast_anim_time = _config.get_float("player.cast_anim_time", 0.18)
	cast.emit("nova")


## Lumos: widens the wizard's light for a while. In dark zones it is the only way to see.
func _cast_lumos(delta: float) -> void:
	var p := "spells.lumos."
	if lumos_allowed and Input.is_action_just_pressed("cast_lumos") and _lumos_time <= 0.0 and _lumos_cooldown <= 0.0:
		_lumos_time = _config.get_float(p + "duration", 8.0) + _skills.get_modifier("lumos.duration")
		cast.emit("lumos")
	if _lumos_time > 0.0:
		_lumos_time -= delta
		if _lumos_time <= 0.0:
			_lumos_cooldown = _config.get_float(p + "cooldown", 3.0)
			_lumos_cooldown_max = _lumos_cooldown
	var lit: bool = _lumos_time > 0.0
	var radius: float = _config.get_float(p + "idle_radius", 90.0)
	if lit:
		radius = _config.get_float(p + "radius", 300.0) * (1.0 + _skills.get_modifier("lumos.radius_mult"))
	var target_scale: float = radius / (LIGHT_TEXTURE_SIZE * 0.5)
	_light.texture_scale = lerpf(_light.texture_scale, target_scale, clampf(8.0 * delta, 0.0, 1.0))
	if _lumos_orb:
		_lumos_orb.visible = lit
		_lumos_orb.position = cast_origin() - global_position + aim * _config.get_float("spells.bolt.muzzle_offset", 34.0)


func _build_light() -> void:
	_light = PointLight2D.new()
	_light.texture = Fx.radial_light_texture(LIGHT_TEXTURE_SIZE)
	_light.color = _config.get_color("spells.lumos.color", Color(1, 0.95, 0.8))
	_light.energy = _config.get_float("spells.lumos.energy", 1.3)
	_light.position = Vector2(0, -_config.get_vec2("player.hitbox", Vector2(42, 130)).y * 0.5)
	_light.texture_scale = _config.get_float("spells.lumos.idle_radius", 90.0) / (LIGHT_TEXTURE_SIZE * 0.5)
	add_child(_light)
	_lumos_orb = Node2D.new()
	add_child(_lumos_orb)
	if SpriteHook.attach_effect(_lumos_orb, _config, "lumos_orb") == null:
		_lumos_orb.queue_free()
		_lumos_orb = null


func _heart_capacity() -> int:
	return maxi(1, _config.get_int("player.max_hearts", 1) + int(_skills.get_modifier("player.max_hearts")))


func _on_upgrades_changed() -> void:
	var capacity: int = _heart_capacity()
	if capacity > _max_hearts:
		# A new heart arrives full.
		_hearts += capacity - _max_hearts
	_max_hearts = capacity
	hearts_changed.emit(_hearts, _max_hearts)


func _cast_levitate(delta: float) -> void:
	var p := "spells.levitate."
	if _grabbed != null and not is_instance_valid(_grabbed):
		_grabbed = null
	if _grabbed == null:
		if Input.is_action_just_pressed("cast_levitate") and _levitate_cooldown <= 0.0:
			_grabbed = _find_grab_target()
			if _grabbed:
				_grabbed.grab()
				_grab_time = 0.0
				cast.emit("grab")
		return
	_grab_time += delta
	var hold_point := cast_origin() + aim * _config.get_float(p + "hold_distance", 70.0)
	_grabbed.set_hold_target(hold_point)
	if not Input.is_action_pressed("cast_levitate") or _grab_time >= _config.get_float(p + "max_hold_time", 2.5):
		_release_grab(true)


func _release_grab(throw_it: bool) -> void:
	if _grabbed == null or not is_instance_valid(_grabbed):
		_grabbed = null
		return
	var p := "spells.levitate."
	var explode: float = _config.get_float(p + "explode_radius", 120.0) if _skills.get_modifier("levitate.explode") > 0.0 else 0.0
	var speed: float = _config.get_float(p + "throw_speed", 1050.0) if throw_it else 0.0
	_grabbed.throw(aim * speed, explode)
	_grabbed = null
	_levitate_cooldown = maxf(
		_config.get_float(p + "cooldown", 1.1) + _skills.get_modifier("levitate.cooldown"),
		_config.get_float(p + "min_cooldown", 0.25))
	_levitate_cooldown_max = _levitate_cooldown
	cast.emit("throw")


func _find_grab_target() -> Enemy:
	var p := "spells.levitate."
	var mouse := get_global_mouse_position()
	var allow_heavy: bool = _skills.get_modifier("levitate.heavy") > 0.0
	var best: Enemy = null
	var best_distance: float = _config.get_float(p + "grab_radius", 110.0)
	var max_range: float = _config.get_float(p + "range", 380.0)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or not enemy.can_be_grabbed(allow_heavy):
			continue
		if enemy.global_position.distance_to(global_position) > max_range:
			continue
		var d: float = enemy.global_position.distance_to(mouse)
		if d < best_distance:
			best_distance = d
			best = enemy
	return best


## Dashing through an enemy kills it; each kill refunds the dash so kills chain.
func _dash_strike() -> void:
	var allow_heavy: bool = _skills.get_modifier("move.dash_heavy") > 0.0
	var knock: float = _config.get_float("player.dash_kill_knockback", 450.0)
	for body: Node2D in _hurtbox.get_overlapping_bodies():
		var enemy := body as Enemy
		if enemy == null or not enemy.is_dangerous() or (enemy.heavy and not allow_heavy):
			continue
		enemy.hit(enemy.hp, Vector2(_dash_dir * knock, -knock * 0.5), "dash")
		if bool(_config.get_value("player.dash_refund_on_kill", true)):
			_dash_cooldown = 0.0
		cast.emit("dash_kill")


func _check_hurt() -> void:
	if is_invulnerable():
		return
	for body: Node2D in _hurtbox.get_overlapping_bodies():
		if body is Enemy and (body as Enemy).is_dangerous():
			take_hit(body.global_position)
			return


## Picks the animation for the current state. Cast overrides movement briefly.
func _animate(delta: float) -> void:
	_cast_anim_time -= delta
	if _cast_anim_time > 0.0 and SpriteHook.has_anim(self, "cast"):
		SpriteHook.play(self, "cast")
	elif not is_on_floor() and SpriteHook.has_anim(self, "jump"):
		SpriteHook.hold_frame(self, "jump", 0 if velocity.y < 0.0 else 1)
	elif absf(velocity.x) > _config.get_float("player.run_anim_threshold", 30.0):
		# Moving against the facing (backpedalling while aiming): run cycle in reverse.
		SpriteHook.play(self, "run", signf(velocity.x) != _facing)
	else:
		SpriteHook.play(self, "idle")


func _draw() -> void:
	if _has_art:
		return
	if _grabbed != null and is_instance_valid(_grabbed):
		draw_line(Vector2(0, -28), _grabbed.global_position - global_position, _config.get_color("debug.held"), 2.0)
	DebugBox.draw(self, _config.get_vec2("player.hitbox", Vector2(26, 44)) * _squash, _config.get_color("debug.player"), is_invulnerable())
	draw_line(Vector2(0, -28), Vector2(0, -28) + aim * 30.0, _config.get_color("debug.text_dim"), 2.0)
