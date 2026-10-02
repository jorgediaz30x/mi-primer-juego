class_name BossOrb
extends Area2D
## Morvane's projectile. Kills the player on touch (unless dashing), bursts on the floor.

var config: GameConfig
var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 4.0
var radius: float = 16.0

var _has_art: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.WORLD | Layers.PLAYER
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)
	_has_art = SpriteHook.attach_effect(self, config, "boss_orb") != null


func _physics_process(delta: float) -> void:
	position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		var player := body as Player
		if player.is_invulnerable():
			return
		player.take_hit(global_position)
	Fx.play(get_parent(), config, "hit_spark", global_position, config.get_color("debug.enemy"))
	queue_free()


func _draw() -> void:
	if not _has_art:
		draw_circle(Vector2.ZERO, radius, config.get_color("debug.npc"))
