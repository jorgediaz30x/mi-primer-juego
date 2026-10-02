class_name Bolt
extends Area2D
## "Fulgor" projectile: flies straight, damages active enemies, dies on walls.

var velocity: Vector2 = Vector2.ZERO
var damage: int = 1
var pierce: int = 0
var lifetime: float = 0.9
var radius: float = 7.0
var knockback: float = 160.0
var color: Color = Color.WHITE
var config: GameConfig
var has_art: bool = false

var _already_hit: Dictionary = {}


func _ready() -> void:
	collision_layer = Layers.PLAYER_PROJECTILE
	collision_mask = Layers.WORLD | Layers.ENEMY
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)
	rotation = velocity.angle()
	has_art = SpriteHook.attach_effect(self, config, "bolt") != null


func _physics_process(delta: float) -> void:
	position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body is Enemy:
		var enemy := body as Enemy
		if not enemy.is_dangerous() or _already_hit.has(enemy):
			return
		_already_hit[enemy] = true
		enemy.hit(damage, velocity.normalized() * knockback)
		Fx.play(get_parent(), config, "hit_spark", global_position, color)
		_micro_hitstop()
		if pierce <= 0:
			queue_free()
		else:
			pierce -= 1
	else:
		Fx.play(get_parent(), config, "hit_spark", global_position, color)
		queue_free()


func _draw() -> void:
	if not has_art:
		draw_circle(Vector2.ZERO, radius, color)


## A frame-long freeze on every hit: sells the impact without slowing the game.
func _micro_hitstop() -> void:
	var duration: float = config.get_float("feel.hitstop_hit", 0.012)
	if duration <= 0.0 or Engine.time_scale < 1.0:
		return
	Engine.time_scale = config.get_float("feel.hitstop_scale", 0.05)
	# The bolt is freed on impact, and a freed object's callbacks are disconnected:
	# restoring the time scale must not depend on it, so it is bound to Engine.
	get_tree().create_timer(duration, true, false, true).timeout.connect(Engine.set_time_scale.bind(1.0))
