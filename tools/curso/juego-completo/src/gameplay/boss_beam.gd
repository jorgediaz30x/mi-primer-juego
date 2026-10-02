class_name BossBeam
extends Node2D
## Horizontal beam across the arena. WARNING (thin flashing line, harmless) ->
## ACTIVE (hurts a player overlapping its band) -> frees itself.
##
## Transition table:
##   WARNING --(warning_time elapsed)--> ACTIVE --(active_time elapsed)--> done

enum State { WARNING, ACTIVE }

var config: GameConfig
var target: Player
## Arena x range [left, right].
var span: Vector2 = Vector2(0, 1280)
## World y of the beam centre.
var y: float = 500.0
var thickness: float = 90.0
var warning_time: float = 0.9
var active_time: float = 0.9

var _state: State = State.WARNING
var _t: float = 0.0
var _art: AnimatedSprite2D


func _ready() -> void:
	position = Vector2((span.x + span.y) * 0.5, y)


func _process(delta: float) -> void:
	_t += delta
	match _state:
		State.WARNING:
			if _t >= warning_time:
				_state = State.ACTIVE
				_t = 0.0
				_attach_art()
		State.ACTIVE:
			_check_hit()
			if _t >= active_time:
				queue_free()
	queue_redraw()


func _attach_art() -> void:
	_art = SpriteHook.attach_effect(self, config, "beam")
	if _art:
		var texture := _art.sprite_frames.get_frame_texture(_art.animation, 0)
		_art.scale = Vector2((span.y - span.x) / texture.get_width(), thickness / texture.get_height())


func _check_hit() -> void:
	if target == null or not is_instance_valid(target) or not target.alive:
		return
	var height: float = config.get_vec2("player.hitbox", Vector2(42, 130)).y
	var top: float = target.global_position.y - height
	var bottom: float = target.global_position.y
	if bottom > y - thickness * 0.5 and top < y + thickness * 0.5:
		target.take_hit(Vector2(target.global_position.x, y))


func _draw() -> void:
	var half: float = (span.y - span.x) * 0.5
	if _state == State.WARNING:
		# Flashing guide line + band edges: where the beam will be.
		var on: bool = int(_t * 12.0) % 2 == 0
		var c := config.get_color("debug.warning")
		c.a = 0.9 if on else 0.35
		draw_line(Vector2(-half, 0), Vector2(half, 0), c, 4.0)
		c.a *= 0.4
		draw_rect(Rect2(-half, -thickness * 0.5, half * 2.0, thickness), c, false, 2.0)
	elif _art == null:
		draw_rect(Rect2(-half, -thickness * 0.5, half * 2.0, thickness), config.get_color("debug.npc"))
