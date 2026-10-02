class_name RingFx
extends Node2D
## Expanding, fading ring. Frees itself when done.

const DURATION := 0.3

var color: Color = Color.WHITE
var max_radius: float = 100.0

var _t: float = 0.0


func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k: float = _t / DURATION
	var c := color
	c.a = 1.0 - k
	draw_arc(Vector2.ZERO, max_radius * (0.3 + 0.7 * k), 0.0, TAU, 40, c, 6.0 * (1.0 - k) + 1.0)
