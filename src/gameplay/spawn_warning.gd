class_name SpawnWarning
extends Node2D
## Marker shown where an enemy or attack is about to appear. One-hit death needs
## fair warning. Plays the generated vfx.spawn_warning, else a gray-box pulse.

var config: GameConfig
var color: Color = Color.RED

var _t: float = 0.0
var _has_art: bool = false


func _ready() -> void:
	if config:
		_has_art = SpriteHook.attach_effect(self, config, "spawn_warning") != null


func _process(delta: float) -> void:
	_t += delta
	if not _has_art:
		queue_redraw()


func _draw() -> void:
	if _has_art:
		return
	var pulse: float = 0.6 + 0.4 * sin(_t * 30.0)
	var c := color
	c.a = pulse
	draw_arc(Vector2.ZERO, 16.0 + 4.0 * pulse, 0.0, TAU, 24, c, 3.0)
