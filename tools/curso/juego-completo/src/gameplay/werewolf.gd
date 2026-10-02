class_name Werewolf
extends Enemy
## Werewolf: stalks, telegraphs with a flash, then charges across the floor.

enum Phase { STALK, TELEGRAPH, CHARGE, RECOVER }

## Emitted when it starts winding up a charge (the roar).
signal telegraphed

var _phase: Phase = Phase.STALK
var _phase_timer: float = 0.0
var _charge_dir: float = 1.0
var _speed: float
var _accel: float
var _charge_speed: float
var _charge_range: float
var _vertical_tolerance: float
var _telegraph_time: float
var _charge_time: float
var _recover_time: float


## Reads tuning from config. Call after [method Enemy.setup].
func configure() -> void:
	var p := "enemies.werewolf."
	hp = config.get_int(p + "hp", 4)
	xp_value = config.get_int(p + "xp", 60)
	health_max = hp
	show_health_bar = bool(config.get_value(p + "show_health_bar", true))
	points_value = config.get_int(p + "points", 400)
	heavy = true
	gravity = config.get_float(p + "gravity", 2000.0)
	body_size = config.get_vec2(p + "size", Vector2(44, 62))
	_speed = config.get_float(p + "speed", 115.0)
	_accel = config.get_float(p + "accel", 900.0)
	_charge_speed = config.get_float(p + "charge_speed", 720.0)
	_charge_range = config.get_float(p + "charge_range", 430.0)
	_vertical_tolerance = config.get_float(p + "charge_vertical_tolerance", 70.0)
	_telegraph_time = config.get_float(p + "telegraph_time", 0.45)
	_charge_time = config.get_float(p + "charge_time", 0.75)
	_recover_time = config.get_float(p + "recover_time", 0.6)


func _ready() -> void:
	super._ready()
	has_art = SpriteHook.attach_character(self, config, "werewolf", "walk")


## True while it is winding up a charge (the level uses it for a warning cue).
func is_telegraphing() -> bool:
	return _phase == Phase.TELEGRAPH


func _behave(delta: float) -> void:
	var to_player: Vector2 = target.global_position - global_position
	velocity.y += gravity * delta
	_phase_timer -= delta
	match _phase:
		Phase.STALK:
			velocity.x = move_toward(velocity.x, signf(to_player.x) * _speed, _accel * delta)
			if is_on_floor() and absf(to_player.x) < _charge_range and absf(to_player.y) < _vertical_tolerance:
				_phase = Phase.TELEGRAPH
				_phase_timer = _telegraph_time
				telegraphed.emit()
				_charge_dir = signf(to_player.x)
		Phase.TELEGRAPH:
			velocity.x = move_toward(velocity.x, 0.0, _accel * 2.0 * delta)
			if _phase_timer <= 0.0:
				_phase = Phase.CHARGE
				_phase_timer = _charge_time
		Phase.CHARGE:
			velocity.x = _charge_dir * _charge_speed
			if _phase_timer <= 0.0 or is_on_wall():
				_phase = Phase.RECOVER
				_phase_timer = _recover_time
		Phase.RECOVER:
			velocity.x = move_toward(velocity.x, 0.0, _accel * 3.0 * delta)
			if _phase_timer <= 0.0:
				_phase = Phase.STALK
	move_and_slide()
	match _phase:
		Phase.TELEGRAPH:
			SpriteHook.play(self, "roar")
		Phase.CHARGE:
			SpriteHook.play(self, "charge")
		_:
			SpriteHook.play(self, "walk")


func _art_tint() -> Color:
	if _phase == Phase.TELEGRAPH and _flash <= 0.0:
		return config.get_color("feel_tints.telegraph", Color(2.2, 0.6, 0.6))
	return super._art_tint()


func _draw_body() -> void:
	var color := config.get_color("debug.warning") if _phase == Phase.TELEGRAPH else config.get_color("debug.enemy_heavy")
	DebugBox.draw(self, body_size, tint(color))
