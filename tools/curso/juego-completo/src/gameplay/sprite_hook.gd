class_name SpriteHook
extends RefCounted
## Plugs the generated pixel art into any Node2D, replacing its gray-box.
##
## Art comes from game_config.json, written by tools/art/generate_art.py:
##   animations.<who>.<anim> = {frames: [res paths], fps, loop}   -> AnimatedSprite2D
##   sprites.<who>           = res path                           -> Sprite2D (fallback)
## Every piece of art is scaled by the same integer render.pixel_scale with
## nearest filtering, so all assets share one pixel density.
## The attached node is always a child named "Art" with its feet at the owner's
## origin (bottom-centre), or centred for projectiles and effects.
##
## Usage:
##   has_art = SpriteHook.attach_character(self, config, "hero", "idle")
##   SpriteHook.play(self, "run")
##   SpriteHook.face(self, -1.0)

const ART_NODE := "Art"
const ANCHORS_META := "feet_anchors"


## Loads a texture, or null when the path is empty or not imported.
static func load_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## Builds SpriteFrames from an animations dictionary ({anim: {frames, fps, loop}}).
## Returns null when no animation has a loadable frame.
static func build_frames(animations: Dictionary) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var anchors: Dictionary = {}
	for anim: String in animations:
		var def: Variant = animations[anim]
		if not def is Dictionary:
			continue
		var textures: Array[Texture2D] = []
		for path: Variant in (def as Dictionary).get("frames", []):
			var texture := load_texture(str(path))
			if texture:
				textures.append(texture)
		if textures.is_empty():
			continue
		frames.add_animation(anim)
		frames.set_animation_speed(anim, float((def as Dictionary).get("fps", 10)))
		frames.set_animation_loop(anim, bool((def as Dictionary).get("loop", true)))
		for texture in textures:
			frames.add_frame(anim, texture)
		var anchor: Variant = (def as Dictionary).get("anchor")
		if anchor is Array and (anchor as Array).size() >= 2:
			anchors[anim] = Vector2(float(anchor[0]), float(anchor[1]))
	frames.set_meta(ANCHORS_META, anchors)
	return frames if not frames.get_animation_names().is_empty() else null


## Attaches a character's art: animated when configured, else its static sprite.
## [param first_anim] is played immediately. Returns true when art was attached.
static func attach_character(owner: Node2D, config: GameConfig, who: String, first_anim: String = "") -> bool:
	var scale: float = config.get_float("render.pixel_scale", 3.0)
	var animations: Variant = config.get_value("animations." + who, {})
	var frames: SpriteFrames = build_frames(animations) if animations is Dictionary else null
	if frames:
		var animated := AnimatedSprite2D.new()
		animated.name = ART_NODE
		animated.sprite_frames = frames
		animated.centered = false
		animated.scale = Vector2(scale, scale)
		owner.add_child(animated)
		var names := frames.get_animation_names()
		play(owner, first_anim if frames.has_animation(first_anim) else String(names[0]))
		return true
	var texture := load_texture(config.get_text("sprites." + who))
	if texture == null:
		return false
	var sprite := Sprite2D.new()
	sprite.name = ART_NODE
	sprite.texture = texture
	sprite.centered = false
	sprite.scale = Vector2(scale, scale)
	sprite.offset = Vector2(-texture.get_width() * 0.5, -texture.get_height())
	owner.add_child(sprite)
	return true


## Attaches a centred animated effect/projectile from vfx.<name>. Returns the node or null.
static func attach_effect(owner: Node2D, config: GameConfig, effect: String) -> AnimatedSprite2D:
	var def: Variant = config.get_value("vfx." + effect)
	if not def is Dictionary:
		return null
	var frames := build_frames({effect: def})
	if frames == null:
		return null
	var scale: float = config.get_float("render.pixel_scale", 3.0)
	var animated := AnimatedSprite2D.new()
	animated.name = ART_NODE
	animated.sprite_frames = frames
	animated.scale = Vector2(scale, scale)
	owner.add_child(animated)
	animated.play(effect)
	return animated


## Plays [param anim] on the owner's art if it exists (no-op for static art),
## re-anchoring the frame so the feet stay on the owner's origin.
## [param backwards] plays it in reverse (backpedalling).
static func play(owner: Node2D, anim: String, backwards: bool = false) -> void:
	var art := owner.get_node_or_null(ART_NODE) as AnimatedSprite2D
	if art == null or not art.sprite_frames.has_animation(anim):
		return
	var reversed: bool = art.get_playing_speed() < 0.0
	if art.animation != anim or not art.is_playing() or reversed != backwards:
		if backwards:
			art.play_backwards(anim)
		else:
			art.play(anim)
	_anchor(art)


## Places the current animation's feet anchor on the owner's origin. A flipped
## sprite mirrors inside its own rect, so the feet move to (width - anchor.x).
static func _anchor(art: AnimatedSprite2D) -> void:
	var anim := art.animation
	var texture := art.sprite_frames.get_frame_texture(anim, 0)
	if texture == null:
		return
	var width: float = texture.get_width()
	var anchors: Dictionary = art.sprite_frames.get_meta(ANCHORS_META, {})
	var feet: Vector2 = anchors.get(anim, Vector2(width * 0.5, texture.get_height()))
	var x: float = width - feet.x if art.flip_h else feet.x
	art.offset = Vector2(-x, -feet.y)


## Shows a fixed frame of [param anim] (e.g. jump rising/falling). Clamped to range.
static func hold_frame(owner: Node2D, anim: String, frame: int) -> void:
	var art := owner.get_node_or_null(ART_NODE) as AnimatedSprite2D
	if art == null or not art.sprite_frames.has_animation(anim):
		return
	play(owner, anim)
	art.pause()
	art.frame = clampi(frame, 0, art.sprite_frames.get_frame_count(anim) - 1)


## Whether the owner's art has an animation called [param anim].
static func has_anim(owner: Node2D, anim: String) -> bool:
	var art := owner.get_node_or_null(ART_NODE) as AnimatedSprite2D
	return art != null and art.sprite_frames.has_animation(anim)


## Tints the attached art (hit flash, telegraph, invulnerability). WHITE = untinted.
static func tint(owner: Node2D, color: Color) -> void:
	var art := owner.get_node_or_null(ART_NODE) as CanvasItem
	if art:
		art.modulate = color


## Flips the attached art to face [param direction] (-1 left, +1 right).
## Generated art faces right (see tools/art/asset_manifest.json).
static func face(owner: Node2D, direction: float) -> void:
	var art := owner.get_node_or_null(ART_NODE)
	if art == null:
		return
	var flip: bool = direction < 0.0
	if art.get("flip_h") == flip:
		return
	art.set("flip_h", flip)
	# Static fallback art is centred horizontally, so flipping keeps its feet in place.
	if art is AnimatedSprite2D and not (art as AnimatedSprite2D).centered:
		_anchor(art as AnimatedSprite2D)
