class_name Fx
extends RefCounted
## One-shot visual effects. Plays the generated animation (vfx.<name> in
## game_config.json) when it exists; falls back to a plain particle burst.


## Plays effect [param effect] at [param at] under [param parent]. The fallback
## burst uses [param fallback_color]. Frees itself when finished.
static func play(parent: Node, config: GameConfig, effect: String, at: Vector2, fallback_color: Color = Color.WHITE) -> void:
	var holder := Node2D.new()
	holder.position = at
	parent.add_child(holder)
	var art := SpriteHook.attach_effect(holder, config, effect)
	if art:
		art.animation_finished.connect(holder.queue_free)
		return
	holder.queue_free()
	burst(parent, at, fallback_color)


## A soft radial light texture ([param size] px) for PointLight2D. Shared by
## Lumos and the crystal lights; texture_scale = radius / (size * 0.5).
static func radial_light_texture(size: int) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = size
	texture.height = size
	return texture


## Spawns a radial particle burst at [param at] under [param parent] (gray-box fallback).
static func burst(parent: Node, at: Vector2, color: Color, amount: int = 18, speed: float = 320.0) -> void:
	var particles := CPUParticles2D.new()
	particles.position = at
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = amount
	particles.lifetime = 0.55
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.gravity = Vector2(0, 900)
	particles.initial_velocity_min = speed * 0.4
	particles.initial_velocity_max = speed
	particles.scale_amount_min = 2.5
	particles.scale_amount_max = 6.0
	particles.color = color
	parent.add_child(particles)
	particles.emitting = true
	parent.get_tree().create_timer(1.2, true, false, true).timeout.connect(particles.queue_free)


## Spawns an expanding ring (gray-box fallback for explosions).
static func ring(parent: Node, at: Vector2, color: Color, radius: float) -> void:
	var node := RingFx.new()
	node.position = at
	node.color = color
	node.max_radius = radius
	parent.add_child(node)
