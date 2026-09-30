class_name Enemy
extends CharacterBody2D
## Shared enemy behaviour: health, flashing, and the Aerum hold/throw states.
##
## Subclasses implement [method _behave] (the ACTIVE AI) and [method _draw_body].

## Emitted once when the enemy dies. [param how]: "bolt", "thrown", "impact", "explosion", "dash".
signal killed(enemy: Enemy, how: String)
## Emitted when a thrown enemy with the explode upgrade hits something.
signal exploded(at: Vector2, radius: float)
## Emitted when a hit lands but does not kill (for hurt sounds).
signal damaged(enemy: Enemy, how: String)

enum State { ACTIVE, HELD, THROWN, DEAD }

var state: State = State.ACTIVE
var hp: int = 1
## XP granted when killed (before the combo multiplier).
var xp_value: int = 1
## Starting hp, for the health bar.
var health_max: int = 1
## Draw a small health bar above the head once hurt (tough enemies).
var show_health_bar: bool = false
var points_value: int = 100
var heavy: bool = false
var gravity: float = 1800.0
var body_size: Vector2 = Vector2(30, 20)
var target: Node2D
var config: GameConfig
var has_art: bool = false

var _flash: float = 0.0
var _hold_target: Vector2 = Vector2.ZERO
var _hold_stiffness: float = 18.0
var _thrown_damage: int = 2
var _explode_radius: float = 0.0
var _thrown_hits: Dictionary = {}
var _detector: Area2D
var _anim_time: float = 0.0


## Injects dependencies. Call before adding to the tree.
func setup(cfg: GameConfig, player: Node2D) -> void:
	config = cfg
	target = player
	_hold_stiffness = cfg.get_float("spells.levitate.hold_stiffness", 18.0)
	_thrown_damage = cfg.get_int("spells.levitate.thrown_damage", 2)


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = Layers.ENEMY
	collision_mask = Layers.WORLD
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = body_size
	shape.shape = rect
	shape.position = Vector2(0, -body_size.y * 0.5)
	add_child(shape)

	_detector = Area2D.new()
	_detector.collision_layer = 0
	_detector.collision_mask = Layers.ENEMY
	var detector_shape := CollisionShape2D.new()
	var detector_rect := RectangleShape2D.new()
	detector_rect.size = body_size * 1.2
	detector_shape.shape = detector_rect
	detector_shape.position = shape.position
	_detector.add_child(detector_shape)
	add_child(_detector)


## True while touching this enemy kills the player.
func is_dangerous() -> bool:
	return state == State.ACTIVE


## Whether Aerum can lift this enemy.
func can_be_grabbed(allow_heavy: bool) -> bool:
	return state == State.ACTIVE and (not heavy or allow_heavy)


## Applies damage and knockback. Dies at 0 hp.
func hit(damage: int, knock: Vector2, how: String = "bolt") -> void:
	if state == State.DEAD:
		return
	hp -= damage
	_flash = 0.09
	velocity += knock
	if hp <= 0:
		die(how)
	else:
		damaged.emit(self, how)


## Aerum grabbed this enemy.
func grab() -> void:
	state = State.HELD
	velocity = Vector2.ZERO


## Where Aerum wants the enemy to float to this frame.
func set_hold_target(point: Vector2) -> void:
	_hold_target = point


## Aerum released the enemy as a projectile.
func throw(throw_velocity: Vector2, explode_radius: float) -> void:
	state = State.THROWN
	velocity = throw_velocity
	_explode_radius = explode_radius


## Kills the enemy (idempotent).
func die(how: String) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	killed.emit(self, how)
	queue_free()


func _physics_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_anim_time += delta
	match state:
		State.ACTIVE:
			_behave(delta)
		State.HELD:
			velocity = (_hold_target - global_position) * _hold_stiffness
			move_and_slide()
		State.THROWN:
			_fly_thrown(delta)
	if absf(velocity.x) > 1.0:
		SpriteHook.face(self, signf(velocity.x))
	if has_art:
		SpriteHook.tint(self, _art_tint())
	queue_redraw()


func _fly_thrown(delta: float) -> void:
	velocity.y += gravity * 0.3 * delta
	move_and_slide()
	for body: Node2D in _detector.get_overlapping_bodies():
		if body != self and body is Enemy and (body as Enemy).is_dangerous() and not _thrown_hits.has(body):
			_thrown_hits[body] = true
			(body as Enemy).hit(_thrown_damage, velocity.normalized() * 300.0, "thrown")
	if get_slide_collision_count() > 0:
		if _explode_radius > 0.0:
			exploded.emit(global_position, _explode_radius)
		die("impact")


## ACTIVE-state AI. Override in subclasses.
func _behave(_delta: float) -> void:
	pass


## Placeholder art. Override in subclasses.
func _draw_body() -> void:
	pass


## Art modulate for this frame. Subclasses extend it (telegraph warnings).
func _art_tint() -> Color:
	if state == State.HELD or state == State.THROWN:
		return config.get_color("feel_tints.held", Color(0.6, 1.6, 2.0))
	return config.get_color("feel_tints.hit_flash", Color(3, 3, 3)) if _flash > 0.0 else Color.WHITE


## Base colour, or white while flashing from a hit.
func tint(base: Color) -> Color:
	return Color.WHITE if _flash > 0.0 else base


func _draw() -> void:
	if not has_art and (state == State.HELD or state == State.THROWN):
		draw_rect(Rect2(Vector2(-body_size.x * 0.5, -body_size.y) - Vector2(4, 4), body_size + Vector2(8, 8)), config.get_color("debug.held"), false, 2.0)
	if not has_art:
		_draw_body()
	if show_health_bar and state == State.ACTIVE:
		_draw_health_bar()


func _draw_health_bar() -> void:
	var width: float = config.get_float("ui.enemy_bar.width", 90.0)
	var height: float = config.get_float("ui.enemy_bar.height", 10.0)
	var art_top: float = body_size.y * config.get_float("ui.enemy_bar.art_height_ratio", 1.15)
	var at := Vector2(-width * 0.5, -art_top - config.get_float("ui.enemy_bar.offset", 18.0))
	draw_rect(Rect2(at - Vector2(2, 2), Vector2(width + 4, height + 4)), Color(0.02, 0.02, 0.05, 0.9))
	var ratio: float = clampf(float(hp) / float(maxi(1, health_max)), 0.0, 1.0)
	draw_rect(Rect2(at, Vector2(width * ratio, height)), config.get_color("ui.danger"))
