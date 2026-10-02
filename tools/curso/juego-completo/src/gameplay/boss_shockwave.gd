class_name BossShockwave
extends Node2D
## A wave rolling along the floor. Hurts a grounded player it touches: jump it.
## Frees itself at the arena edge.

var config: GameConfig
var direction: float = 1.0
var speed: float = 620.0
## Hit box: width x height above the floor line (the node sits on the floor).
var size: Vector2 = Vector2(90, 60)
## Arena x range [left, right].
var bounds: Vector2 = Vector2(0, 1280)

var _art: AnimatedSprite2D
var _hit: bool = false


func _ready() -> void:
	_art = SpriteHook.attach_effect(self, config, "shockwave")
	if _art:
		_art.flip_h = direction < 0.0
		_art.offset = Vector2(0, -_art.sprite_frames.get_frame_texture(_art.animation, 0).get_height() * 0.5)


func _physics_process(delta: float) -> void:
	position.x += direction * speed * delta
	if position.x < bounds.x - size.x or position.x > bounds.y + size.x:
		queue_free()
		return
	if _hit:
		return
	for node: Node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		if player == null or not player.alive:
			continue
		var feet: Vector2 = player.global_position
		if absf(feet.x - global_position.x) < size.x * 0.5 and feet.y > global_position.y - size.y:
			player.take_hit(global_position)
			_hit = true


func _draw() -> void:
	if _art == null:
		draw_rect(Rect2(-size.x * 0.5, -size.y, size.x, size.y), config.get_color("debug.npc"))
