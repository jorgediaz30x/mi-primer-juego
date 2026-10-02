class_name Spider
extends Enemy
## Shadow spider. Enters from the sides, drops from the canopy, or bursts from the ground.

enum Phase { DESCENDING, HANGING, FALLING, CRAWLING, LEAPING }

var mode: String = "side"

var _phase: Phase = Phase.CRAWLING
var _speed: float
var _accel: float
var _hop_velocity: float
var _hop_cooldown: float
var _hop_timer: float = 0.0
var _hang_y: float
var _descend_speed: float
var _drop_trigger: float
var _hang_timer: float
var _leap_velocity: float
var _leap_side_speed: float
var _lunge_range: float
var _lunge_speed: float
var _lunge_velocity: float
var _lunge_cooldown: float
var _lunge_timer: float = 0.0


## Configures spawn behaviour. [param spawn_mode]: "side", "ceiling" or "burrow".
func configure(spawn_mode: String, rng: RandomNumberGenerator) -> void:
	mode = spawn_mode
	var p := "enemies.spider."
	hp = config.get_int(p + "hp", 1)
	xp_value = config.get_int(p + "xp", 12)
	gravity = config.get_float(p + "gravity", 1800.0)
	body_size = config.get_vec2(p + "size", Vector2(30, 18))
	_speed = config.get_float(p + "speed", 175.0) * rng.randf_range(0.85, 1.15)
	_accel = config.get_float(p + "accel", 1400.0)
	_hop_velocity = config.get_float(p + "hop_velocity", -580.0)
	_hop_cooldown = config.get_float(p + "hop_cooldown", 1.2)
	_hop_timer = rng.randf_range(0.3, _hop_cooldown)
	_hang_y = rng.randf_range(config.get_float(p + "hang_min_y", 110.0), config.get_float(p + "hang_max_y", 240.0))
	_descend_speed = config.get_float(p + "descend_speed", 260.0)
	_drop_trigger = config.get_float(p + "drop_trigger_distance", 90.0)
	_hang_timer = config.get_float(p + "max_hang_time", 1.6)
	_leap_velocity = config.get_float(p + "burrow_leap_velocity", -980.0)
	_leap_side_speed = config.get_float(p + "burrow_side_speed", 160.0)
	_lunge_range = config.get_float(p + "lunge_range", 150.0)
	_lunge_speed = config.get_float(p + "lunge_speed", 520.0)
	_lunge_velocity = config.get_float(p + "lunge_velocity", -380.0)
	_lunge_cooldown = config.get_float(p + "lunge_cooldown", 1.1)
	_lunge_timer = rng.randf_range(0.2, _lunge_cooldown)
	points_value = config.get_int(p + "points", 100)


func _ready() -> void:
	super._ready()
	has_art = SpriteHook.attach_character(self, config, "spider", "crawl")
	match mode:
		"ceiling":
			_phase = Phase.DESCENDING
			collision_mask = 0
		"burrow":
			_phase = Phase.LEAPING
			collision_mask = 0
			velocity = Vector2(signf(target.global_position.x - global_position.x) * _leap_side_speed, _leap_velocity)
		_:
			_phase = Phase.CRAWLING


func _behave(delta: float) -> void:
	match _phase:
		Phase.DESCENDING:
			global_position.y = move_toward(global_position.y, _hang_y, _descend_speed * delta)
			if is_equal_approx(global_position.y, _hang_y):
				_phase = Phase.HANGING
		Phase.HANGING:
			_hang_timer -= delta
			if absf(target.global_position.x - global_position.x) < _drop_trigger or _hang_timer <= 0.0:
				_phase = Phase.FALLING
				collision_mask = Layers.WORLD
		Phase.FALLING:
			velocity.y += gravity * delta
			move_and_slide()
			if is_on_floor():
				_phase = Phase.CRAWLING
		Phase.LEAPING:
			velocity.y += gravity * delta
			if velocity.y > 0.0:
				collision_mask = Layers.WORLD
			move_and_slide()
			if is_on_floor():
				_phase = Phase.CRAWLING
		Phase.CRAWLING:
			_crawl(delta)
	if _phase == Phase.DESCENDING or _phase == Phase.HANGING:
		SpriteHook.hold_frame(self, "crawl", 0)
	else:
		SpriteHook.play(self, "crawl")


func _crawl(delta: float) -> void:
	var dx: float = target.global_position.x - global_position.x
	velocity.x = move_toward(velocity.x, signf(dx) * _speed, _accel * delta)
	velocity.y += gravity * delta
	_hop_timer -= delta
	_lunge_timer -= delta
	var player_above: bool = target.global_position.y < global_position.y - 60.0
	var same_height: bool = absf(target.global_position.y - global_position.y) < 50.0
	if is_on_floor() and _lunge_timer <= 0.0 and same_height and absf(dx) < _lunge_range:
		velocity = Vector2(signf(dx) * _lunge_speed, _lunge_velocity)
		_lunge_timer = _lunge_cooldown
	elif is_on_floor() and _hop_timer <= 0.0 and (player_above or is_on_wall()) and absf(dx) < 260.0:
		velocity.y = _hop_velocity
		_hop_timer = _hop_cooldown
	move_and_slide()


func _draw_body() -> void:
	if _phase == Phase.DESCENDING or _phase == Phase.HANGING:
		draw_line(Vector2(0, -global_position.y), Vector2.ZERO, config.get_color("debug.text_dim"), 1.0)
	DebugBox.draw(self, body_size, tint(config.get_color("debug.enemy")))
