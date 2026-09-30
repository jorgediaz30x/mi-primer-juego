class_name LevelUpScreen
extends CanvasLayer
## "Pick 1 of 3" upgrade cards, shown on level-up (or when a new area unlocks
## cards) while the game is paused. Display only: choices go out as signals.
##
## Rules (handicaps, on purpose):
##   - a countdown (progression.pick_time): when it runs out the offer is lost;
##   - when the deck is full, a new card replaces the OLDEST one (shown on the
##     card) — there is no choosing what to drop; "keep" skips the offer.
## Keys 1..4 pick at once; clicks only after progression.pick_click_delay, so the
## click that was firing Fulgor cannot pick a card by accident.

## The player chose upgrade [param id]; [param replaced] is the card it
## replaces ("" when there was a free slot).
signal picked(id: String, replaced: String)
## The player kept their current upgrades.
signal kept
## The countdown ran out: the offer is lost.
signal expired

const CARD_SIZE := Vector2(340, 400)
const CARD_GAP := 36.0

var _config: GameConfig
var _deck: UpgradeDeck
var _root: Control
var _title: Label
var _subtitle: Label
var _timer_label: Label
var _cards_root: Control
var _offer: Array[String] = []
var _click_armed_in: float = 0.0
var _time_left: float = 0.0


## Injects dependencies. Call before adding to the tree.
func setup(cfg: GameConfig, deck: UpgradeDeck) -> void:
	_config = cfg
	_deck = deck


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := UiStyle.dim(0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)
	_title = UiStyle.label(_config, "", "huge", "accent")
	_title.position = Vector2(0, 24)
	_title.size = Vector2(1280, 90)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_title)
	_subtitle = UiStyle.label(_config, "", "normal")
	_subtitle.position = Vector2(0, 110)
	_subtitle.size = Vector2(1280, 36)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_subtitle)
	_timer_label = UiStyle.label(_config, "", "big", "danger")
	_timer_label.position = Vector2(0, 590)
	_timer_label.size = Vector2(1280, 50)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_timer_label)
	_cards_root = Control.new()
	_cards_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cards_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_cards_root)
	hide()


## Shows [param offer] (upgrade ids) under [param heading] (e.g. "¡NIVEL 5!").
func open(offer: Array[String], heading: String) -> void:
	_offer = offer
	_title.text = heading
	var full: bool = _deck.is_full()
	_subtitle.text = _config.get_text("names.ui_offer_full") % _deck.max_owned if full \
		else _config.get_text("names.ui_level_up_subtitle")
	for child in _cards_root.get_children():
		child.queue_free()
	var total: float = offer.size() * CARD_SIZE.x + (offer.size() - 1) * CARD_GAP
	var x0: float = (1280.0 - total) * 0.5
	for i in offer.size():
		_build_card(i, offer[i], Vector2(x0 + i * (CARD_SIZE.x + CARD_GAP), 160), full)
	if full:
		_build_keep_button(offer.size() + 1)
	_click_armed_in = _config.get_float("progression.pick_click_delay", 0.5)
	_time_left = _config.get_float("progression.pick_time", 10.0)
	show()


func _build_card(index: int, id: String, at: Vector2, full: bool) -> void:
	var def := _deck.get_def(id)
	var box := UiStyle.panel(_config, CARD_SIZE)
	box.position = at
	_cards_root.add_child(box)

	var category := UiStyle.label(_config, _config.get_text("upgrades.categories." + str(def.get("category", ""))), "small")
	category.position = at + Vector2(0, 20)
	category.size = Vector2(CARD_SIZE.x, 26)
	category.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cards_root.add_child(category)

	var icon := TextureRect.new()
	icon.texture = UiStyle.icon(_config, UiStyle.icon_index(_config, str(def.get("icon", id))))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = at + Vector2((CARD_SIZE.x - 136) * 0.5, 50)
	icon.size = Vector2(136, 136)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_root.add_child(icon)

	var title := UiStyle.label(_config, str(def.get("name", id)), "big", "accent")
	_cards_root.add_child(title)
	title.position = at + Vector2(10, 194)
	title.size = Vector2(CARD_SIZE.x - 20, 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var desc := UiStyle.label(_config, str(def.get("description", "")), "normal")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cards_root.add_child(desc)
	desc.position = at + Vector2(20, 242)
	desc.custom_minimum_size = Vector2(CARD_SIZE.x - 40, 0)
	desc.size = Vector2(CARD_SIZE.x - 40, 64)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if full:
		var oldest: String = _deck.oldest()
		var loses := UiStyle.label(_config, _config.get_text("names.ui_card_replaces") % str(_deck.get_def(oldest).get("name", oldest)), "small", "danger")
		_cards_root.add_child(loses)
		loses.position = at + Vector2(0, CARD_SIZE.y - 84)
		loses.size = Vector2(CARD_SIZE.x, 28)
		loses.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var stacks: int = _deck.stacks_of(id)
	var footer: String = _config.get_text("names.ui_card_new") if stacks == 0 \
		else _config.get_text("names.ui_card_stack") % [stacks, stacks + 1]
	var footer_label := UiStyle.label(_config, "%s   [%d]" % [footer, index + 1], "normal", "accent")
	_cards_root.add_child(footer_label)
	footer_label.position = at + Vector2(0, CARD_SIZE.y - 48)
	footer_label.size = Vector2(CARD_SIZE.x, 32)
	footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_add_click_area(box, at, CARD_SIZE, _choose.bind(id))


func _build_keep_button(key: int) -> void:
	var at := Vector2(440, 640)
	var size := Vector2(400, 56)
	var box := UiStyle.panel(_config, size)
	box.position = at
	_cards_root.add_child(box)
	var label := UiStyle.label(_config, _config.get_text("names.ui_keep_upgrades") % key, "normal", "accent")
	_cards_root.add_child(label)
	label.position = at + Vector2(0, 12)
	label.size = Vector2(size.x, 32)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_add_click_area(box, at, size, _keep)


func _add_click_area(box: CanvasItem, at: Vector2, size: Vector2, action: Callable) -> void:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.position = at
	button.size = size
	button.pressed.connect(func() -> void:
		if _click_armed_in <= 0.0:
			action.call())
	button.mouse_entered.connect(func() -> void: box.modulate = Color(1.25, 1.2, 1.0))
	button.mouse_exited.connect(func() -> void: box.modulate = Color.WHITE)
	_cards_root.add_child(button)


func _process(delta: float) -> void:
	if not visible:
		return
	_click_armed_in -= delta
	_time_left -= delta
	_timer_label.text = _config.get_text("names.ui_pick_timer") % ceili(maxf(_time_left, 0.0))
	# The last seconds pulse so the pressure is felt.
	_timer_label.modulate.a = 1.0 if _time_left > 3.0 or int(_time_left * 6.0) % 2 == 0 else 0.35
	if _time_left <= 0.0:
		hide()
		expired.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	for i in 4:
		if event.is_action_pressed("pick_%d" % (i + 1)):
			get_viewport().set_input_as_handled()
			if i < _offer.size():
				_choose(_offer[i])
			elif _deck.is_full() and i == _offer.size():
				_keep()
			return


func _choose(id: String) -> void:
	hide()
	picked.emit(id, _deck.oldest() if _deck.is_full() else "")


func _keep() -> void:
	hide()
	kept.emit()
