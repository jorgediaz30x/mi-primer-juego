class_name DebugBox
extends RefCounted
## Gray-box placeholder: a flat rectangle the size of the collision box.
## Not art — it only exists until the GPT Image sprite is configured.


## Draws a box of [param size] with its bottom-centre at the node origin.
static func draw(canvas: CanvasItem, size: Vector2, color: Color, hollow: bool = false) -> void:
	var rect := Rect2(Vector2(-size.x * 0.5, -size.y), size)
	if hollow:
		canvas.draw_rect(rect, color, false, 2.0)
	else:
		canvas.draw_rect(rect, color)
