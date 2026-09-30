class_name Crosshair
extends CanvasLayer
## Aiming reticle that replaces the OS cursor during play. Kicks on every cast.
## The OS cursor comes back while a menu is open ([method set_aiming]).

var _config: GameConfig
var _sprite: Sprite2D
var _base_scale: float = 3.0
var _kick: float = 1.0
var _aiming: bool = true


## Injects config. Call before adding to the tree.
func setup(config: GameConfig) -> void:
	_config = config


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_base_scale = _config.get_float("render.pixel_scale", 3.0)
	_sprite = Sprite2D.new()
	_sprite.texture = SpriteHook.load_texture(_config.get_text("ui.crosshair"))
	_sprite.scale = Vector2(_base_scale, _base_scale)
	add_child(_sprite)
	set_aiming(_sprite.texture != null)


## Shows the reticle and hides the OS cursor (or the reverse, for menus).
func set_aiming(on: bool) -> void:
	_aiming = on and _sprite.texture != null
	_sprite.visible = _aiming
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if _aiming else Input.MOUSE_MODE_VISIBLE


## Connected to Player.cast: the reticle pulses when a spell fires.
func on_player_cast(kind: String) -> void:
	if kind == "bolt":
		_kick = _config.get_float("feel.crosshair_kick", 1.35)


func _process(delta: float) -> void:
	if not _aiming:
		return
	_sprite.position = get_viewport().get_mouse_position()
	_kick = lerpf(_kick, 1.0, clampf(18.0 * delta, 0.0, 1.0))
	_sprite.scale = Vector2.ONE * _base_scale * _kick
	_sprite.rotation += delta * 0.8
